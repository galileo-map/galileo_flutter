use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

use anyhow::anyhow;
use flutter_plugin_sdk::WgpuTexture;
use log::{debug, info};
use parking_lot::Mutex;
use serde_json::{json, Value};

use crate::api::dart_types::{
    LayerConfig, MapInitConfig, MapSize, MapViewport, Point, Polygon, RenderedMapFrame, UserEvent,
};
use crate::core::flutter::wgpu_texture::create_flutter_texture;
use crate::core::map_thread::{
    css_color, BaseStyle, Command, GeoLayerKind, MapThread, MapThreadConfig, RasterSpec, Shared,
};
use crate::core::{SESSIONS, SESSION_COUNTER, TILE_CACHE_PATH};

pub type SessionID = u32;

const OSM_TILES: &str = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

/// Bookkeeping for a feature layer owned by the map thread.
struct ManagedLayer {
    kind: GeoLayerKind,
    next_feature_id: u32,
    feature_ids: HashSet<u32>,
}

/// A map session: a MapLibre renderer thread plus the Flutter texture it feeds.
pub struct MapSession {
    pub session_id: SessionID,
    thread: MapThread,
    shared: Arc<Shared>,
    texture_id: Mutex<i64>,
    managed_layers: Mutex<HashMap<u32, ManagedLayer>>,
    next_layer_id: AtomicU32,
    next_raster_id: AtomicU32,
    is_alive: AtomicBool,
}

impl MapSession {
    pub async fn new(config: MapInitConfig) -> anyhow::Result<Arc<MapSession>> {
        let session_id = create_new_session();
        let (texture, texture_id) = create_flutter_texture(config.map_size)?;
        let (frames, _) = tokio::sync::watch::channel(None);
        let shared = Arc::new(Shared {
            viewport: Mutex::new(None),
            frames,
        });

        let thread = MapThread::spawn(
            MapThreadConfig {
                center: config.latlon,
                // Galileo z-levels address 256px tiles, MapLibre zoom 512px tiles.
                zoom: (f64::from(config.zoom_level) - 1.0).max(0.0),
                size: config.map_size,
                background: config.background_color,
                cache_path: TILE_CACHE_PATH.read().as_ref().map(Into::into),
            },
            texture,
            shared.clone(),
        )?;

        let session = Arc::new(MapSession {
            session_id,
            thread,
            shared,
            texture_id: Mutex::new(texture_id),
            managed_layers: Mutex::new(HashMap::new()),
            next_layer_id: AtomicU32::new(0),
            next_raster_id: AtomicU32::new(0),
            is_alive: AtomicBool::new(true),
        });
        SESSIONS.lock().insert(session_id, session.clone());
        Ok(session)
    }

    pub fn is_alive(&self) -> bool {
        self.is_alive.load(Ordering::SeqCst)
    }

    pub fn mark_alive(&self) {
        self.is_alive.store(true, Ordering::SeqCst);
    }

    pub fn get_flutter_texture_id(&self) -> Option<i64> {
        self.is_alive().then(|| *self.texture_id.lock())
    }

    /// Adds a layer from the Dart-facing configuration.
    pub async fn add_layer(&self, layer: LayerConfig) -> anyhow::Result<()> {
        match layer {
            LayerConfig::Osm => self.add_raster(json!({
                "type": "raster",
                "tiles": [OSM_TILES],
                "tileSize": 256,
                "maxzoom": 19,
                "attribution": "© OpenStreetMap contributors",
            })),
            LayerConfig::RasterTiles {
                url_template,
                attribution,
            } => {
                let mut source = json!({
                    "type": "raster",
                    "tiles": [url_template],
                    "tileSize": 256,
                    "maxzoom": 22,
                });
                if let Some(attribution) = attribution {
                    source["attribution"] = Value::String(attribution);
                }
                self.add_raster(source)
            }
            // `style_json` is a MapLibre style document, or the http(s) URL of
            // one; it replaces the base style. `url_template` and `attribution`
            // come from the style itself.
            LayerConfig::VectorTiles { style_json, .. } => {
                let style = style_json.trim();
                let base = if style.starts_with("http://") || style.starts_with("https://") {
                    BaseStyle::Url(
                        style
                            .parse()
                            .map_err(|e| anyhow!("Invalid vector tile style URL: {e}"))?,
                    )
                } else {
                    serde_json::from_str::<Value>(style)
                        .map_err(|e| anyhow!("Failed to parse vector tile style: {e}"))?;
                    BaseStyle::Json(style.to_owned())
                };
                self.thread.send(Command::SetBaseStyle(base))
            }
            LayerConfig::PolygonLayer { features } => self
                .add_managed_layer(GeoLayerKind::Polygon, features.iter().map(polygon_feature))
                .map(|_| ()),
            LayerConfig::PointLayer { features } => self
                .add_managed_layer(GeoLayerKind::Point, features.iter().map(point_feature))
                .map(|_| ()),
            // Handled by flutter
            LayerConfig::WidgetLayer => Ok(()),
        }
    }

    fn add_raster(&self, source: Value) -> anyhow::Result<()> {
        let id = format!(
            "raster-{}",
            self.next_raster_id.fetch_add(1, Ordering::SeqCst)
        );
        self.thread
            .send(Command::AddRaster(RasterSpec { id, source }))
    }

    fn add_managed_layer(
        &self,
        kind: GeoLayerKind,
        features: impl Iterator<Item = Option<Value>>,
    ) -> anyhow::Result<u32> {
        let layer_id = self.next_layer_id.fetch_add(1, Ordering::SeqCst);
        let mut managed = ManagedLayer {
            kind,
            next_feature_id: 0,
            feature_ids: HashSet::new(),
        };
        let mut initial = Vec::new();
        for feature in features {
            let id = managed.next_feature_id;
            managed.next_feature_id += 1;
            managed.feature_ids.insert(id);
            // Features that cannot be drawn (for example degenerate polygons)
            // keep their id but contribute no geometry.
            if let Some(feature) = feature {
                initial.push((id, feature));
            }
        }
        self.thread.send(Command::AddGeoLayer {
            id: layer_id,
            kind,
            features: initial,
        })?;
        self.managed_layers.lock().insert(layer_id, managed);
        Ok(layer_id)
    }

    pub async fn add_point_layer(&self, points: &[Point]) -> anyhow::Result<u32> {
        self.add_managed_layer(GeoLayerKind::Point, points.iter().map(point_feature))
    }

    pub async fn add_polygon_layer(&self, polygons: &[Polygon]) -> anyhow::Result<u32> {
        self.add_managed_layer(GeoLayerKind::Polygon, polygons.iter().map(polygon_feature))
    }

    fn add_feature(
        &self,
        layer_id: u32,
        kind: GeoLayerKind,
        feature: Option<Value>,
    ) -> anyhow::Result<u32> {
        let mut layers = self.managed_layers.lock();
        let layer = layers
            .get_mut(&layer_id)
            .ok_or_else(|| anyhow!("Layer {layer_id} not found"))?;
        if layer.kind != kind {
            return Err(anyhow!("Layer {layer_id} type mismatch"));
        }
        let id = layer.next_feature_id;
        layer.next_feature_id += 1;
        layer.feature_ids.insert(id);
        if let Some(feature) = feature {
            self.thread.send(Command::AddGeoFeature {
                layer: layer_id,
                id,
                feature,
            })?;
        }
        Ok(id)
    }

    fn remove_feature(
        &self,
        layer_id: u32,
        kind: GeoLayerKind,
        feature_id: u32,
    ) -> anyhow::Result<bool> {
        let mut layers = self.managed_layers.lock();
        let layer = layers
            .get_mut(&layer_id)
            .ok_or_else(|| anyhow!("Layer {layer_id} not found"))?;
        if layer.kind != kind {
            return Err(anyhow!("Layer {layer_id} type mismatch"));
        }
        if !layer.feature_ids.remove(&feature_id) {
            return Ok(false);
        }
        self.thread.send(Command::RemoveGeoFeature {
            layer: layer_id,
            id: feature_id,
        })?;
        Ok(true)
    }

    pub async fn add_point_to_layer(&self, layer_id: u32, point: Point) -> anyhow::Result<u32> {
        self.add_feature(layer_id, GeoLayerKind::Point, point_feature(&point))
    }

    pub async fn add_polygon_to_layer(
        &self,
        layer_id: u32,
        polygon: Polygon,
    ) -> anyhow::Result<u32> {
        self.add_feature(layer_id, GeoLayerKind::Polygon, polygon_feature(&polygon))
    }

    pub async fn remove_point_from_layer(
        &self,
        layer_id: u32,
        feature_id: u32,
    ) -> anyhow::Result<bool> {
        self.remove_feature(layer_id, GeoLayerKind::Point, feature_id)
    }

    pub async fn remove_polygon_from_layer(
        &self,
        layer_id: u32,
        feature_id: u32,
    ) -> anyhow::Result<bool> {
        self.remove_feature(layer_id, GeoLayerKind::Polygon, feature_id)
    }

    /// Requests a fresh frame.
    pub async fn redraw(&self) -> anyhow::Result<()> {
        self.thread.send(Command::Redraw)
    }

    pub fn handle_event(&self, event: UserEvent) {
        let _ = self.thread.send(Command::Event(event));
    }

    pub fn subscribe_rendered_frames(
        &self,
    ) -> tokio::sync::watch::Receiver<Option<RenderedMapFrame>> {
        self.shared.frames.subscribe()
    }

    pub async fn get_viewport(&self) -> Option<MapViewport> {
        *self.shared.viewport.lock()
    }

    /// Resizes the rendering session and returns the new Flutter texture id.
    pub async fn resize(&self, new_size: MapSize) -> anyhow::Result<i64> {
        info!(
            "Resizing session {} to {}x{}",
            self.session_id, new_size.width, new_size.height
        );
        let (texture, texture_id) = create_flutter_texture(new_size)?;
        self.thread.resize(texture, new_size).await?;
        *self.texture_id.lock() = texture_id;
        Ok(texture_id)
    }

    /// Stops the map thread and returns its textures so the caller can drop them.
    pub async fn terminate(self: Arc<Self>) -> Vec<WgpuTexture> {
        self.is_alive.store(false, Ordering::SeqCst);
        self.managed_layers.lock().clear();
        self.thread.shutdown().await
    }
}

fn polygon_feature(polygon: &Polygon) -> Option<Value> {
    if polygon.points.len() < 3 {
        return None;
    }
    let mut ring: Vec<Value> = polygon
        .points
        .iter()
        .map(|p| json!([p.longitude, p.latitude]))
        .collect();
    ring.push(ring[0].clone());
    Some(json!({
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [ring]},
        "properties": {
            "fill": css_color(&polygon.style.fill_color),
            "stroke": css_color(&polygon.style.stroke_color),
            "stroke_width": polygon.style.stroke_width,
        },
    }))
}

fn point_feature(point: &Point) -> Option<Value> {
    Some(json!({
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [point.coordinate.longitude, point.coordinate.latitude],
        },
        "properties": {
            "color": css_color(&point.style.fill_color),
            "size": point.style.size,
        },
    }))
}

/// Updates the session counter and returns a new session ID
fn create_new_session() -> SessionID {
    debug!(
        "Session created: {}",
        SESSION_COUNTER.load(Ordering::Relaxed)
    );
    SESSION_COUNTER.fetch_add(1, Ordering::SeqCst) + 1
}
