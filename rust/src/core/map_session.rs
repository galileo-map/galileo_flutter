use crate::api::dart_types::{Point, PointSymbol, Polygon, PolygonSymbol};
use crate::core::galileo_ref::create_galileo_map_v2;
use crate::core::{WindowlessRenderer, SESSIONS, SESSION_COUNTER};
use anyhow::anyhow;
use galileo::layer::{FeatureId, FeatureLayer, RasterTileLayer};
use galileo::{galileo_types, DummyMessenger, Messenger};
use galileo_types::cartesian::Rect;
use galileo_types::geo::impls::GeoPoint2d;
use galileo_types::geometry_type::GeoSpace2d;
use log::{debug, error, info, warn};
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

use flutter_plugin_sdk::PluginError;

use crate::api::dart_types::{MapInitConfig, MapSize, MapViewport, RenderedMapFrame};
use crate::core::flutter::wgpu_texture::{create_flutter_texture, SharedWgpuTexture};

pub type SessionID = u32;

pub struct FlutterCtx {
    texture: SharedWgpuTexture,
    pub texture_id: i64,
}

impl FlutterCtx {
    fn new(size: MapSize) -> anyhow::Result<Self> {
        let (texture, texture_id) = create_flutter_texture(size)?;
        Ok(FlutterCtx {
            texture,
            texture_id,
        })
    }
}

/// Identifies the map view that raster tiles were last scheduled for, so a
/// new tile-loading batch is only spawned when the view actually changed.
#[derive(Clone, Debug, PartialEq)]
struct ScheduledTileView {
    resolution: f64,
    bbox: Option<Rect<f64>>,
}

/// Internal map session that manages the Galileo map with rendering.
pub struct MapSession {
    pub session_id: SessionID,
    pub map: Arc<Mutex<galileo::Map>>,
    /// This is used to manage feature layers as it stores the index of the
    /// feature layer
    managed_layers: Arc<Mutex<HashMap<u32, usize>>>,
    managed_layer_id: std::sync::atomic::AtomicU32,
    renderer: Arc<Mutex<WindowlessRenderer>>,
    /// this is optional because we wanna drop this on the platform thread.
    flutter_ctx: RwLock<Option<FlutterCtx>>,
    /// Texture that was replaced by the latest resize and is kept alive until
    /// Flutter has switched to the new texture id.
    retired_ctx: RwLock<Option<FlutterCtx>>,
    /// Serializes resize and redraw operations so a queued redraw can never
    /// publish pixels for the previous texture size.
    render_lock: Mutex<()>,
    /// Runtime that owns the session's async work. Redraw requests can arrive
    /// from the Rust shell's frame-acquire thread (outside any Tokio runtime),
    /// so redraw loops are spawned on this captured handle instead of relying
    /// on an ambient runtime context.
    runtime_handle: tokio::runtime::Handle,
    /// The last map view for which raster tiles were scheduled. Used to avoid
    /// spawning a new batch of tile-loading tasks on every frame.
    scheduled_tile_view: parking_lot::Mutex<Option<ScheduledTileView>>,
    is_alive: AtomicBool,
    pub controller: galileo::control::MapController,
    // The map is initially built without layers, so the configured zoom level cannot be
    // resolved from a tile schema at construction time.
    zoom_level: u32,
    initial_view_resolved: AtomicBool,
    is_first_render: AtomicBool,
    requires_redraw: AtomicBool,
    redraw_scheduled: AtomicBool,
    rendered_frame_sequence: AtomicU64,
    rendered_frame_tx: tokio::sync::watch::Sender<Option<RenderedMapFrame>>,
}

// Ensure MapSession is Send + Sync for thread safety
unsafe impl Send for MapSession {}
unsafe impl Sync for MapSession {}

#[derive(Clone)]
struct SessionMessenger(Arc<MapSession>);

impl galileo::Messenger for SessionMessenger {
    fn request_redraw(&self) {
        self.0.requires_redraw.store(true, Ordering::Relaxed);

        if self.0.redraw_scheduled.swap(true, Ordering::Acquire) {
            return;
        }

        let session = self.0.clone();
        self.0.runtime_handle.spawn(async move {
            loop {
                const FRAME_THROTTLE_MS: u64 = 16;
                tokio::time::sleep(Duration::from_millis(FRAME_THROTTLE_MS)).await; // throttle to ~60fps
                if !session.requires_redraw.swap(false, Ordering::Relaxed) {
                    session.redraw_scheduled.store(false, Ordering::Release);
                    break;
                }

                session._draw_no_res().await;
            }
        });
    }
}

impl MapSession {
    pub async fn new(config: MapInitConfig) -> anyhow::Result<Arc<MapSession>> {
        let session_id = create_new_session();
        let runtime_handle = tokio::runtime::Handle::current();
        // Create windowless renderer
        let renderer_size = config.map_size.as_galileo();
        let renderer = WindowlessRenderer::new(renderer_size);
        let renderer = Arc::new(Mutex::new(renderer));

        // Create OSM layer for background
        // let mut osm = RasterTileLayerBuilder::new_osm()
        //     // .with_file_cache_checked(".tile_cache")
        //     .build()
        //     .expect("failed to create layer");

        // // If we don't set fade in duration to 0, when the image is first drawn, all tiles will
        // // be transparent.
        // osm.set_fade_in_duration(Duration::default());
        let size = config.map_size;

        // let map = create_galileo_map(&config, osm)?;
        let map = create_galileo_map_v2(&config)?;
        let map = Arc::new(Mutex::new(map));

        let flutter_ctx = FlutterCtx::new(size)?;
        let (rendered_frame_tx, _) = tokio::sync::watch::channel(None);

        let session = Arc::new(MapSession {
            session_id,
            map: map.clone(),
            renderer: renderer.clone(),
            flutter_ctx: RwLock::new(Some(flutter_ctx)),
            retired_ctx: RwLock::new(None),
            render_lock: Mutex::new(()),
            runtime_handle,
            scheduled_tile_view: parking_lot::Mutex::new(None),
            is_alive: AtomicBool::new(true),
            controller: galileo::control::MapController::default(),
            zoom_level: config.zoom_level,
            initial_view_resolved: AtomicBool::new(false),
            is_first_render: AtomicBool::new(true),
            requires_redraw: AtomicBool::new(false),
            redraw_scheduled: AtomicBool::new(false),
            rendered_frame_sequence: AtomicU64::new(0),
            rendered_frame_tx,
            managed_layers: Arc::new(Mutex::new(HashMap::default())),
            managed_layer_id: std::sync::atomic::AtomicU32::new(0),
        });
        // set session as message callback for galileo
        {
            let messenger = SessionMessenger(session.clone());

            let mut map = map.lock().await;
            for layer in map.layers_mut().iter_mut() {
                layer.set_messenger(Arc::new(messenger.clone()) as Arc<dyn galileo::Messenger>);
            }

            map.set_messenger(Some(messenger));
        }

        {
            let mut sessions = SESSIONS.lock();
            sessions.insert(session_id, session.clone());
        }
        Ok(session)
    }

    pub fn is_alive(&self) -> bool {
        self.is_alive.load(Ordering::SeqCst)
    }
    pub fn mark_alive(&self) {
        self.is_alive.store(true, Ordering::SeqCst);
    }

    pub fn get_flutter_texture_id(&self) -> Option<i64> {
        Some(self.flutter_ctx.read().as_ref()?.texture_id)
    }

    pub async fn add_layer(&self, mut layer: impl galileo::layer::Layer + 'static) {
        if let Some(session) = SESSIONS.lock().get(&self.session_id).cloned() {
            let messenger: SessionMessenger = SessionMessenger(session);
            layer.set_messenger(Arc::new(messenger) as Arc<dyn galileo::Messenger>);
        }

        let mut map = self.map.lock().await;

        if !self.initial_view_resolved.load(Ordering::Relaxed) {
            if let Some(schema) = layer.tile_schema() {
                if let Some(resolution) = schema.lod_resolution(self.zoom_level) {
                    let view = map.view().with_resolution(resolution);
                    map.set_view(view);
                    self.initial_view_resolved.store(true, Ordering::Relaxed);
                } else {
                    warn!(
                        "Zoom level {} is not available in the added layer's tile schema; \
                         leaving the initial map resolution unchanged",
                        self.zoom_level
                    );
                }
            }
        }

        map.layers_mut().push(layer);
        map.redraw();
        self.schedule_raster_tiles(&map);
    }

    pub async fn add_managed_layer(&self, mut layer: impl galileo::layer::Layer + 'static) -> u32 {
        if let Some(session) = SESSIONS.lock().get(&self.session_id).cloned() {
            let messenger = SessionMessenger(session);
            layer.set_messenger(Arc::new(messenger) as Arc<dyn Messenger>);
        }
        let layer_id = self.managed_layer_id.fetch_add(1, Ordering::SeqCst);

        let mut map = self.map.lock().await;
        let mut managed = self.managed_layers.lock().await;

        let index = map.layers().len();
        map.layers_mut().push(layer);
        managed.insert(layer_id, index);
        map.redraw();

        layer_id
    }
    pub async fn add_point_to_layer(
        &self,
        layer_id: u32,
        point: Point,
    ) -> anyhow::Result<FeatureId> {
        let mut map = self.map.lock().await;
        let managed = self.managed_layers.lock().await;

        let &index = managed
            .get(&layer_id)
            .ok_or_else(|| anyhow::anyhow!("Layer {} not found", layer_id))?;
        let layer = map
            .layers_mut()
            .get_mut(index)
            .ok_or_else(|| anyhow::anyhow!("Layer at index {} missing", index))?
            .as_any_mut()
            .downcast_mut::<FeatureLayer<GeoPoint2d, Point, PointSymbol, GeoSpace2d>>()
            .ok_or_else(|| anyhow::anyhow!("Layer {} type mismatch on downcast", layer_id))?;

        let feature_id = layer.features_mut().add(point);
        layer.update_feature(feature_id);
        map.redraw();

        Ok(feature_id)
    }

    pub async fn add_polygon_to_layer(
        &self,
        layer_id: u32,
        polygon: Polygon,
    ) -> anyhow::Result<FeatureId> {
        let mut map = self.map.lock().await;
        let managed = self.managed_layers.lock().await;

        let &index = managed
            .get(&layer_id)
            .ok_or_else(|| anyhow::anyhow!("Layer {} not found", layer_id))?;

        let layer = map
            .layers_mut()
            .get_mut(index)
            .ok_or_else(|| anyhow::anyhow!("Layer at index {} missing", index))?
            .as_any_mut()
            .downcast_mut::<FeatureLayer<GeoPoint2d, Polygon, PolygonSymbol, GeoSpace2d>>()
            .ok_or_else(|| anyhow::anyhow!("Layer {} type mismatch on downcast", layer_id))?;

        let feature_id = layer.features_mut().add(polygon);
        layer.update_feature(feature_id);
        map.redraw();

        Ok(feature_id)
    }

    pub async fn remove_point_from_layer(
        &self,
        layer_id: u32,
        feature_id: FeatureId,
    ) -> anyhow::Result<bool> {
        let managed = self.managed_layers.lock().await;
        let &layer_index = managed
            .get(&layer_id)
            .ok_or_else(|| anyhow::anyhow!("Layer {} not found", layer_id))?;

        let mut map = self.map.lock().await;
        let layer = map
            .layers_mut()
            .get_mut(layer_index)
            .ok_or_else(|| anyhow::anyhow!("Layer at index {} missing", layer_index))?
            .as_any_mut()
            .downcast_mut::<FeatureLayer<GeoPoint2d, Point, PointSymbol, GeoSpace2d>>()
            .ok_or_else(|| anyhow::anyhow!("Layer {} type mismatch on downcast", layer_id))?;

        let removed = layer.features_mut().remove(feature_id);
        if removed.is_some() {
            layer.update_all_features();
            map.redraw();
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub async fn remove_polygon_from_layer(
        &self,
        layer_id: u32,
        feature_id: FeatureId,
    ) -> anyhow::Result<bool> {
        let managed = self.managed_layers.lock().await;
        let &layer_index = managed
            .get(&layer_id)
            .ok_or_else(|| anyhow::anyhow!("Layer {} not found", layer_id))?;

        let mut map = self.map.lock().await;
        let layer = map
            .layers_mut()
            .get_mut(layer_index)
            .ok_or_else(|| anyhow::anyhow!("Layer at index {} missing", layer_index))?
            .as_any_mut()
            .downcast_mut::<FeatureLayer<GeoPoint2d, Polygon, PolygonSymbol, GeoSpace2d>>()
            .ok_or_else(|| anyhow::anyhow!("Layer {} type mismatch on downcast", layer_id))?;

        let removed = layer.features_mut().remove(feature_id);
        if removed.is_some() {
            layer.update_all_features();
            map.redraw();
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Renders a single frame for the session.
    pub async fn redraw(&self) -> anyhow::Result<()> {
        let _render_guard = self.render_lock.lock().await;
        let texture = {
            let flctx = self.flutter_ctx.read();
            let flutter_ctx = flctx
                .as_ref()
                .ok_or(anyhow!("flutter context not available"))?;
            flutter_ctx.texture.clone()
        };

        self.redraw_to(&texture).await
    }

    async fn redraw_to(&self, texture: &SharedWgpuTexture) -> anyhow::Result<()> {
        let is_first_render = self.is_first_render.swap(false, Ordering::Relaxed);

        if is_first_render {
            tokio::time::sleep(Duration::from_millis(1000)).await;
        }

        // Prepare the map on the FRB worker thread. GPU command recording is
        // deferred to the shell's frame-acquire callback.
        let (viewport, map_size) = {
            let renderer = self.renderer.lock().await;
            let mut map = self.map.lock().await;

            map.animate();

            // check size changed
            let texture_size = renderer.size();
            let renderer_size = texture_size.cast();
            if map.view().size() != renderer_size {
                map.set_size(renderer_size);
            }

            let viewport = map.view().get_bbox().as_ref().map(MapViewport::from_rect);
            let map_size = MapSize {
                width: texture_size.width(),
                height: texture_size.height(),
            };

            debug!(
                "Rendering map size: {:?} to surface size: {:?}",
                map.view().size(),
                renderer.size()
            );
            debug!("Map view is: {:?}", map.view());
            self.schedule_raster_tiles(&map);
            Self::prepare_non_raster_layers(&map);
            (viewport, map_size)
        };

        let mut frame = match texture.try_next_frame() {
            Ok(frame) => frame,
            Err(PluginError::Busy) => return Ok(()),
            Err(error) => {
                return Err(anyhow::anyhow!(
                    "failed to acquire Rust shell texture frame: {error:?}"
                ));
            }
        };

        let map = self.map.clone();
        let renderer = self.renderer.clone();
        frame
            .render(move |device, encoder, view| {
                let map = map.blocking_lock();
                let mut renderer = renderer.blocking_lock();
                renderer.render(&map, device, encoder, view);
            })
            .map_err(|error| {
                anyhow::anyhow!("failed to record Rust shell texture render: {error:?}")
            })?;
        frame
            .present()
            .map_err(|error| anyhow::anyhow!("failed to present Rust shell texture: {error:?}"))?;

        if let Some(viewport) = viewport {
            let frame = RenderedMapFrame {
                sequence: self.rendered_frame_sequence.fetch_add(1, Ordering::Relaxed) + 1,
                viewport,
                map_size,
            };
            let _ = self.rendered_frame_tx.send(Some(frame));
        }
        Ok(())
    }

    fn schedule_raster_tiles(&self, map: &galileo::Map) {
        let view = map.view().clone();
        let view_key = ScheduledTileView {
            resolution: view.resolution(),
            bbox: view.get_bbox(),
        };

        let mut last_scheduled = self.scheduled_tile_view.lock();
        if last_scheduled.as_ref() == Some(&view_key) {
            return;
        }
        *last_scheduled = Some(view_key);

        for layer in map.layers().iter_visible() {
            let Some(raster_layer) = layer
                .as_any()
                .downcast_ref::<Arc<RwLock<RasterTileLayer>>>()
            else {
                continue;
            };
            let raster_layer = Arc::clone(raster_layer);
            let view = view.clone();
            let runtime = self.runtime_handle.clone();
            runtime.spawn_blocking(move || {
                let tile_runtime = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .expect("failed to build tile-loading runtime");
                tile_runtime.block_on(async move {
                    let layer = raster_layer.read();
                    layer.load_tiles(&view).await;
                });
            });
        }
    }

    fn prepare_non_raster_layers(map: &galileo::Map) {
        for layer in map.layers().iter_visible() {
            if layer
                .as_any()
                .downcast_ref::<Arc<RwLock<RasterTileLayer>>>()
                .is_none()
            {
                layer.prepare(map.view());
            }
        }
    }

    pub fn subscribe_rendered_frames(
        &self,
    ) -> tokio::sync::watch::Receiver<Option<RenderedMapFrame>> {
        self.rendered_frame_tx.subscribe()
    }

    pub async fn get_viewport(&self) -> Option<MapViewport> {
        self.map
            .lock()
            .await
            .view()
            .get_bbox()
            .as_ref()
            .map(MapViewport::from_rect)
    }

    /// Resizes the rendering session.
    pub async fn resize(&self, new_size: MapSize) -> anyhow::Result<i64> {
        info!(
            "Resizing session {} to {}x{}",
            self.session_id, new_size.width, new_size.height
        );
        let new_ctx = FlutterCtx::new(new_size)?;
        let new_texture_id = new_ctx.texture_id;
        let _render_guard = self.render_lock.lock().await;
        let size = galileo_types::cartesian::Size::new(new_size.width, new_size.height);

        // Resize renderer
        {
            let mut renderer = self.renderer.lock().await;
            renderer.resize(size);
        }

        // Resize map view
        {
            let mut map = self.map.lock().await;
            map.set_size(size.cast::<f64>());
        }

        let _ = self.retired_ctx.write().take();
        self.redraw_to(&new_ctx.texture).await?;
        let old_ctx = self.flutter_ctx.write().replace(new_ctx);
        *self.retired_ctx.write() = old_ctx;
        Ok(new_texture_id)
    }

    async fn _draw_no_res(&self) {
        let _ = self.redraw().await.inspect_err(|err| error!("{err}"));
    }

    pub async fn terminate(self: Arc<Self>) -> Option<FlutterCtx> {
        self.is_alive.store(false, Ordering::SeqCst);

        let flctx = self.flutter_ctx.write().take();
        let _ = self.retired_ctx.write().take();
        self.managed_layers.lock().await.clear();

        // clear all layers
        {
            let mut map = self.map.lock().await;
            for layer in map.layers_mut().iter_mut() {
                layer.set_messenger(Arc::new(DummyMessenger {}) as Arc<dyn galileo::Messenger>);
            }
            map.set_messenger(None::<DummyMessenger>);
            map.layers_mut().clear();
        }
        flctx
    }
}
/// Updates the session counter and returns a new session ID
fn create_new_session() -> SessionID {
    debug!(
        "Session created: {}",
        SESSION_COUNTER.load(Ordering::Relaxed)
    );
    SESSION_COUNTER.fetch_add(1, Ordering::SeqCst) + 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_redraw_works_without_an_ambient_runtime() {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .expect("failed to build test runtime");
        let runtime_handle = runtime.handle().clone();

        let (rendered_frame_tx, _) = tokio::sync::watch::channel(None);
        let session = Arc::new(MapSession {
            session_id: 0,
            map: Arc::new(Mutex::new(galileo::MapBuilder::default().build())),
            managed_layers: Arc::new(Mutex::new(HashMap::default())),
            managed_layer_id: std::sync::atomic::AtomicU32::new(0),
            renderer: Arc::new(Mutex::new(WindowlessRenderer::new(
                galileo_types::cartesian::Size::new(1, 1),
            ))),
            flutter_ctx: RwLock::new(None),
            retired_ctx: RwLock::new(None),
            render_lock: Mutex::new(()),
            runtime_handle: runtime_handle.clone(),
            scheduled_tile_view: parking_lot::Mutex::new(None),
            is_alive: AtomicBool::new(true),
            controller: galileo::control::MapController::default(),
            zoom_level: 0,
            initial_view_resolved: AtomicBool::new(true),
            is_first_render: AtomicBool::new(false),
            requires_redraw: AtomicBool::new(false),
            redraw_scheduled: AtomicBool::new(false),
            rendered_frame_sequence: AtomicU64::new(0),
            rendered_frame_tx,
        });

        let messenger = SessionMessenger(session.clone());
        // Simulate Galileo asking for another frame from the Rust shell's
        // frame-acquire thread, where no Tokio runtime is in scope.
        std::thread::spawn(move || messenger.request_redraw())
            .join()
            .expect("redraw request thread panicked");

        runtime.block_on(async {
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        });

        assert!(
            !session.redraw_scheduled.load(Ordering::Acquire),
            "the redraw loop should have completed and cleared its guard"
        );
    }
}
