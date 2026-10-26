//! Dedicated thread that owns the MapLibre Native renderer.
//!
//! `ImageRenderer` is `!Send` and thread-affine, so every interaction with it
//! happens here. The rest of the plugin talks to it through [`Command`]s.
//! MapLibre renders on the shell's wgpu device and queue (the queue only through
//! the SDK's lock-guarded [`GpuQueue`]); each finished frame is copied on the
//! GPU into the shell-owned texture ring that Flutter displays.

use std::collections::BTreeMap;
use std::num::NonZeroU32;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

use flutter_plugin_sdk::gpu::wgpu;
use flutter_plugin_sdk::{GpuQueue, PluginError, WgpuTexture};
use log::{debug, error, warn};
use maplibre_native::{
    AnyLayer, AnySource, CameraUpdate, Continuous, GeoJson, GeoJsonSource, ImageRenderer,
    ImageRendererBuilder, LatLng, QueueOps, ResourceOptions, RunLoopHandle, Size, SourceRefMut,
};
use parking_lot::Mutex;
use serde_json::{json, Value};

use crate::api::dart_types::{
    GalileoColor, GeoLocation, MapSize, MapViewport, MouseButton, RenderedMapFrame, UserEvent,
};
use crate::core::camera::Camera;

const ACTIVE_TICK: Duration = Duration::from_millis(16);
const IDLE_TICK: Duration = Duration::from_millis(50);
const IDLE_AFTER: Duration = Duration::from_secs(2);
const ACK_TIMEOUT: Duration = Duration::from_secs(5);
/// Time constant of the eased zoom: the remaining zoom distance shrinks by
/// `1/e` every `ZOOM_TAU` seconds.
const ZOOM_TAU: f64 = 0.09;
/// Time constant of the velocity decay after a drag is released.
const FLING_TAU: f64 = 0.35;
/// Drags slower than this (px/s) at release do not fling.
const FLING_MIN_SPEED: f64 = 150.0;
/// A fling ends once its speed drops below this (px/s).
const FLING_STOP_SPEED: f64 = 20.0;
/// A release only flings if the last drag event was this recent.
const FLING_MAX_IDLE: Duration = Duration::from_millis(80);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GeoLayerKind {
    Polygon,
    Point,
}

/// Where the base style document comes from.
#[derive(Debug, Clone)]
pub enum BaseStyle {
    Json(String),
    Url(url::Url),
}

/// A raster tile layer, described as style-spec JSON.
pub struct RasterSpec {
    pub id: String,
    pub source: Value,
}

pub enum Command {
    /// Replaces the base style (and re-applies every overlay layer on top).
    SetBaseStyle(BaseStyle),
    AddRaster(RasterSpec),
    AddGeoLayer {
        id: u32,
        kind: GeoLayerKind,
        features: Vec<(u32, Value)>,
    },
    AddGeoFeature {
        layer: u32,
        id: u32,
        feature: Value,
    },
    RemoveGeoFeature {
        layer: u32,
        id: u32,
    },
    Event(UserEvent),
    Redraw,
    /// Swaps in a texture of a new size and renders into it before replying.
    Resize {
        texture: WgpuTexture,
        size: MapSize,
        done: tokio::sync::oneshot::Sender<()>,
    },
    /// Stops the thread and hands the textures back so they can be dropped on
    /// the caller's thread.
    Shutdown(tokio::sync::oneshot::Sender<Vec<WgpuTexture>>),
}

/// State shared between the map thread and the session.
pub struct Shared {
    pub viewport: Mutex<Option<MapViewport>>,
    pub frames: tokio::sync::watch::Sender<Option<RenderedMapFrame>>,
}

pub struct MapThreadConfig {
    pub center: GeoLocation,
    pub zoom: f64,
    pub size: MapSize,
    pub background: GalileoColor,
    pub cache_path: Option<PathBuf>,
}

#[derive(Clone)]
pub struct MapThread {
    tx: mpsc::Sender<Command>,
}

impl MapThread {
    /// Spawns the thread and waits until the renderer and base style are ready.
    pub fn spawn(
        config: MapThreadConfig,
        texture: WgpuTexture,
        shared: Arc<Shared>,
    ) -> anyhow::Result<Self> {
        let (tx, rx) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        std::thread::Builder::new()
            .name("maplibre-map".into())
            .spawn(move || match MapState::new(config, texture, shared) {
                Ok(state) => {
                    let _ = ready_tx.send(Ok(()));
                    state.run(rx);
                }
                Err(err) => {
                    let _ = ready_tx.send(Err(err));
                }
            })?;
        ready_rx
            .recv_timeout(Duration::from_secs(30))
            .map_err(|e| anyhow::anyhow!("map thread did not start: {e}"))??;
        Ok(Self { tx })
    }

    pub fn send(&self, command: Command) -> anyhow::Result<()> {
        self.tx
            .send(command)
            .map_err(|_| anyhow::anyhow!("map thread has stopped"))
    }

    pub async fn resize(&self, texture: WgpuTexture, size: MapSize) -> anyhow::Result<()> {
        let (done, rx) = tokio::sync::oneshot::channel();
        self.send(Command::Resize {
            texture,
            size,
            done,
        })?;
        tokio::time::timeout(ACK_TIMEOUT, rx)
            .await
            .map_err(|_| anyhow::anyhow!("timed out resizing map"))?
            .map_err(|_| anyhow::anyhow!("map thread stopped during resize"))
    }

    pub async fn shutdown(&self) -> Vec<WgpuTexture> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        if self.send(Command::Shutdown(tx)).is_err() {
            return Vec::new();
        }
        tokio::time::timeout(ACK_TIMEOUT, rx)
            .await
            .ok()
            .and_then(Result::ok)
            .unwrap_or_default()
    }
}

/// Routes MapLibre's queue operations through the shell's lock-guarded queue.
struct SharedQueueAdapter(Arc<dyn GpuQueue>);

impl QueueOps for SharedQueueAdapter {
    fn submit(&self, commands: Vec<wgpu::CommandBuffer>) {
        self.0.submit(commands);
    }
    fn write_buffer(&self, buffer: &wgpu::Buffer, offset: wgpu::BufferAddress, data: &[u8]) {
        self.0.write_buffer(buffer, offset, data);
    }
    fn write_texture(
        &self,
        texture: wgpu::TexelCopyTextureInfo<'_>,
        data: &[u8],
        layout: wgpu::TexelCopyBufferLayout,
        size: wgpu::Extent3d,
    ) {
        self.0.write_texture(texture, data, layout, size);
    }
}

struct GeoLayer {
    kind: GeoLayerKind,
    features: Vec<(u32, Value)>,
}

struct MapState {
    renderer: ImageRenderer<Continuous>,
    shared: Arc<Shared>,
    needs_frame: Arc<AtomicBool>,
    base_style: BaseStyle,
    rasters: Vec<RasterSpec>,
    geo: BTreeMap<u32, GeoLayer>,
    camera: Camera,
    size: MapSize,
    texture: Option<WgpuTexture>,
    retired: Option<WgpuTexture>,
    /// The newest MapLibre frame that has not been copied into Flutter's ring yet.
    pending_frame: Option<wgpu::Texture>,
    sequence: AtomicU64,
    zoom_target: Option<ZoomTarget>,
    /// Fling velocity in px/s.
    fling: Option<(f64, f64)>,
    drag: DragTracker,
    last_animation: Instant,
}

/// An eased zoom in progress, anchored at a screen position.
#[derive(Clone, Copy)]
struct ZoomTarget {
    zoom: f64,
    px: f64,
    py: f64,
}

/// Smoothed velocity of the current drag, for flinging on release.
struct DragTracker {
    last_event: Option<Instant>,
    velocity: (f64, f64),
}

fn default_style(background: &GalileoColor) -> String {
    json!({
        "version": 8,
        "name": "galileo_flutter",
        "sources": {},
        "layers": [{
            "id": "background",
            "type": "background",
            "paint": {"background-color": css_color(background)}
        }]
    })
    .to_string()
}

pub fn css_color(color: &GalileoColor) -> String {
    let channel = |v: f64| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
    format!(
        "rgba({},{},{},{})",
        channel(color.r),
        channel(color.g),
        channel(color.b),
        color.a.clamp(0.0, 1.0)
    )
}

fn non_zero(value: u32) -> NonZeroU32 {
    NonZeroU32::new(value.max(1)).expect("value is at least 1")
}

fn geo_source_id(layer: u32) -> String {
    format!("geo-{layer}")
}

fn feature_collection(features: &[(u32, Value)]) -> Value {
    json!({
        "type": "FeatureCollection",
        "features": features.iter().map(|(_, f)| f.clone()).collect::<Vec<_>>(),
    })
}

fn geo_layers_json(layer: u32, kind: GeoLayerKind) -> Vec<Value> {
    let source = geo_source_id(layer);
    match kind {
        GeoLayerKind::Polygon => vec![
            json!({
                "id": format!("{source}-fill"),
                "type": "fill",
                "source": source,
                "paint": {"fill-color": ["to-color", ["get", "fill"]]}
            }),
            json!({
                "id": format!("{source}-line"),
                "type": "line",
                "source": source,
                "layout": {"line-join": "round"},
                "paint": {
                    "line-color": ["to-color", ["get", "stroke"]],
                    "line-width": ["to-number", ["get", "stroke_width"]]
                }
            }),
        ],
        GeoLayerKind::Point => vec![json!({
            "id": format!("{source}-circle"),
            "type": "circle",
            "source": source,
            "paint": {
                "circle-color": ["to-color", ["get", "color"]],
                "circle-radius": ["/", ["to-number", ["get", "size"]], 2]
            }
        })],
    }
}

impl MapState {
    fn new(
        config: MapThreadConfig,
        texture: WgpuTexture,
        shared: Arc<Shared>,
    ) -> anyhow::Result<Self> {
        let mut builder = ImageRendererBuilder::new()
            .with_size(non_zero(config.size.width), non_zero(config.size.height));
        if let Some(path) = config.cache_path {
            builder =
                builder.with_resource_options(ResourceOptions::default().with_cache_path(path));
        }
        let mut renderer = builder.build_continuous_renderer();
        let gpu = crate::rust_shell::gpu_textures()?;
        let device = gpu
            .device()
            .map_err(|e| anyhow::anyhow!("shell exposes no wgpu device: {e:?}"))?;
        let queue = gpu
            .queue()
            .map_err(|e| anyhow::anyhow!("shell exposes no shared GPU queue: {e:?}"))?;
        renderer.set_device_queue_ops(device, Arc::new(SharedQueueAdapter(queue)));

        let needs_frame = Arc::new(AtomicBool::new(true));
        {
            let needs_frame = needs_frame.clone();
            renderer.set_render_requested_callback(move || {
                needs_frame.store(true, Ordering::Release);
            });
        }

        let mut state = Self {
            renderer,
            shared,
            needs_frame,
            base_style: BaseStyle::Json(default_style(&config.background)),
            rasters: Vec::new(),
            geo: BTreeMap::new(),
            camera: Camera::new(config.center, config.zoom),
            size: config.size,
            texture: Some(texture),
            retired: None,
            pending_frame: None,
            sequence: AtomicU64::new(0),
            zoom_target: None,
            fling: None,
            drag: DragTracker {
                last_event: None,
                velocity: (0.0, 0.0),
            },
            last_animation: Instant::now(),
        };
        state.reload_style();
        Ok(state)
    }

    fn run(mut self, rx: mpsc::Receiver<Command>) {
        let run_loop = RunLoopHandle::current();
        let mut last_activity = Instant::now();
        'outer: loop {
            let tick = if last_activity.elapsed() > IDLE_AFTER {
                IDLE_TICK
            } else {
                ACTIVE_TICK
            };
            match rx.recv_timeout(tick) {
                Ok(command) => {
                    last_activity = Instant::now();
                    if !self.handle(command) {
                        break 'outer;
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
            while let Ok(command) = rx.try_recv() {
                last_activity = Instant::now();
                if !self.handle(command) {
                    break 'outer;
                }
            }

            if self.animate() {
                last_activity = Instant::now();
            }
            run_loop.tick();
            if self.needs_frame.swap(false, Ordering::AcqRel) {
                last_activity = Instant::now();
                self.render_frame();
            }
            if self.pending_frame.is_some() {
                last_activity = Instant::now();
                self.present_pending();
            }
        }
        debug!("map thread exiting");
    }

    /// Returns `false` when the thread should stop.
    fn handle(&mut self, command: Command) -> bool {
        match command {
            Command::SetBaseStyle(style) => {
                self.base_style = style;
                self.reload_style();
            }
            Command::AddRaster(spec) => {
                self.apply_raster(&spec);
                self.rasters.push(spec);
            }
            Command::AddGeoLayer { id, kind, features } => {
                self.geo.insert(id, GeoLayer { kind, features });
                self.apply_geo_layer(id);
            }
            Command::AddGeoFeature { layer, id, feature } => {
                if let Some(geo) = self.geo.get_mut(&layer) {
                    geo.features.push((id, feature));
                    self.update_geo_source(layer);
                }
            }
            Command::RemoveGeoFeature { layer, id } => {
                if let Some(geo) = self.geo.get_mut(&layer) {
                    geo.features.retain(|(fid, _)| *fid != id);
                    self.update_geo_source(layer);
                }
            }
            Command::Event(event) => self.handle_event(event),
            Command::Redraw => self.needs_frame.store(true, Ordering::Release),
            Command::Resize {
                texture,
                size,
                done,
            } => {
                self.size = size;
                self.renderer.set_map_size(Size {
                    width: size.width.max(1),
                    height: size.height.max(1),
                });
                self.retired = self.texture.replace(texture);
                self.apply_camera();
                self.needs_frame.store(false, Ordering::Release);
                self.render_frame();
                // The new texture must hold a frame before Flutter switches to it.
                let deadline = Instant::now() + Duration::from_millis(250);
                while self.pending_frame.is_some() && Instant::now() < deadline {
                    self.present_pending();
                    if self.pending_frame.is_some() {
                        std::thread::sleep(Duration::from_millis(4));
                    }
                }
                let _ = done.send(());
            }
            Command::Shutdown(reply) => {
                let textures = [self.texture.take(), self.retired.take()];
                let _ = reply.send(textures.into_iter().flatten().collect());
                return false;
            }
        }
        true
    }

    fn handle_event(&mut self, event: UserEvent) {
        match event {
            UserEvent::ButtonPressed(MouseButton::Left, _) => {
                // A touch-down stops a fling in progress.
                self.fling = None;
                self.drag.last_event = None;
                self.drag.velocity = (0.0, 0.0);
            }
            UserEvent::Drag(MouseButton::Left, delta, event) => {
                let (w, h) = self.screen_size();
                let p = event.screen_pointer_position;
                self.fling = None;
                self.track_drag(delta.dx, delta.dy);
                self.camera.pan(delta.dx, delta.dy, p.x, p.y, w, h);
                self.apply_camera();
            }
            UserEvent::Rotate(degrees, anchor) => {
                let (w, h) = self.screen_size();
                self.fling = None;
                self.camera.rotate_by(degrees, anchor.x, anchor.y, w, h);
                self.apply_camera();
            }
            UserEvent::Pitch(degrees) => {
                self.camera.pitch_by(degrees);
                self.apply_camera();
            }
            UserEvent::ButtonReleased(MouseButton::Left, _)
            | UserEvent::DragEnded(MouseButton::Left, _) => self.release_drag(),
            UserEvent::Zoom(factor, point) => self.request_zoom(factor, point.x, point.y),
            UserEvent::Scroll(delta, event) => {
                let p = event.screen_pointer_position;
                self.request_zoom(0.9f64.powf(delta), p.x, p.y);
            }
            UserEvent::DoubleClick(MouseButton::Left, event) => {
                let p = event.screen_pointer_position;
                self.request_zoom(0.5, p.x, p.y);
            }
            _ => {}
        }
    }

    fn screen_size(&self) -> (f64, f64) {
        (f64::from(self.size.width), f64::from(self.size.height))
    }

    fn track_drag(&mut self, dx: f64, dy: f64) {
        let now = Instant::now();
        let instant = match self.drag.last_event {
            Some(last) if now.duration_since(last) < FLING_MAX_IDLE => {
                let dt = now.duration_since(last).as_secs_f64().max(0.004);
                let (vx, vy) = (dx / dt, dy / dt);
                // Blend with the previous estimate to ride out uneven event spacing.
                (
                    0.5 * self.drag.velocity.0 + 0.5 * vx,
                    0.5 * self.drag.velocity.1 + 0.5 * vy,
                )
            }
            _ => (0.0, 0.0),
        };
        self.drag.velocity = instant;
        self.drag.last_event = Some(now);
    }

    fn release_drag(&mut self) {
        let recent = self
            .drag
            .last_event
            .take()
            .is_some_and(|last| last.elapsed() < FLING_MAX_IDLE);
        let (vx, vy) = std::mem::take(&mut self.drag.velocity);
        if recent && vx.hypot(vy) >= FLING_MIN_SPEED {
            self.fling = Some((vx, vy));
        }
    }

    /// Eases towards the zoom implied by `factor` (an applied resolution
    /// multiplier, below 1 zooms in) around the screen position `(px, py)`.
    fn request_zoom(&mut self, factor: f64, px: f64, py: f64) {
        if !factor.is_finite() || factor <= 0.0 {
            return;
        }
        self.fling = None;
        let base = self.zoom_target.map_or(self.camera.zoom, |t| t.zoom);
        let zoom = (base - factor.log2())
            .clamp(crate::core::camera::MIN_ZOOM, crate::core::camera::MAX_ZOOM);
        self.zoom_target = Some(ZoomTarget { zoom, px, py });
    }

    /// Advances eased zoom and fling by the time since the last call.
    /// Returns whether an animation is still running.
    fn animate(&mut self) -> bool {
        let now = Instant::now();
        let dt = now
            .duration_since(std::mem::replace(&mut self.last_animation, now))
            .as_secs_f64()
            .min(0.05);
        if self.zoom_target.is_none() && self.fling.is_none() {
            return false;
        }
        let (w, h) = (f64::from(self.size.width), f64::from(self.size.height));

        if let Some(target) = self.zoom_target {
            let remaining = target.zoom - self.camera.zoom;
            let step = if remaining.abs() < 0.002 {
                remaining
            } else {
                remaining * (1.0 - (-dt / ZOOM_TAU).exp())
            };
            let before = self.camera.zoom;
            self.camera
                .zoom_by_resolution(2f64.powf(-step), target.px, target.py, w, h);
            if (target.zoom - self.camera.zoom).abs() < 1e-6 || self.camera.zoom == before {
                self.zoom_target = None;
            }
        }
        if let Some((vx, vy)) = self.fling {
            self.camera.pan(vx * dt, vy * dt, w / 2.0, h / 2.0, w, h);
            let decay = (-dt / FLING_TAU).exp();
            let (vx, vy) = (vx * decay, vy * decay);
            self.fling = (vx.hypot(vy) >= FLING_STOP_SPEED).then_some((vx, vy));
        }
        self.apply_camera();
        self.zoom_target.is_some() || self.fling.is_some()
    }

    fn apply_camera(&mut self) {
        let center = self.camera.center();
        self.renderer.update_camera(
            &CameraUpdate::new()
                .center(LatLng {
                    lat: center.latitude,
                    lng: center.longitude,
                })
                .zoom(self.camera.zoom)
                .bearing(self.camera.bearing)
                .pitch(self.camera.pitch),
        );
        *self.shared.viewport.lock() = Some(
            self.camera
                .viewport(f64::from(self.size.width), f64::from(self.size.height)),
        );
        self.needs_frame.store(true, Ordering::Release);
    }

    fn reload_style(&mut self) {
        let loaded = match &self.base_style {
            BaseStyle::Json(json) => self.renderer.load_style_from_json_str(json).wait(),
            BaseStyle::Url(url) => self.renderer.load_style_from_url(url).wait(),
        };
        if let Err(err) = loaded {
            error!("failed to load base style, falling back to an empty style: {err}");
            let fallback = default_style(&GalileoColor::default());
            if let Err(err) = self.renderer.load_style_from_json_str(&fallback).wait() {
                error!("failed to load fallback style: {err}");
                return;
            }
        }
        let rasters = std::mem::take(&mut self.rasters);
        for spec in &rasters {
            self.apply_raster(spec);
        }
        self.rasters = rasters;
        let ids: Vec<u32> = self.geo.keys().copied().collect();
        for id in ids {
            self.apply_geo_layer(id);
        }
        self.apply_camera();
    }

    fn apply_raster(&mut self, spec: &RasterSpec) {
        let source = match AnySource::from_json_value(&spec.id, &spec.source) {
            Ok(source) => source,
            Err(err) => return error!("invalid raster source {}: {err}", spec.id),
        };
        let layer = json!({"id": spec.id, "type": "raster", "source": spec.id});
        let layer = match AnyLayer::from_json_value(&layer) {
            Ok(layer) => layer,
            Err(err) => return error!("invalid raster layer {}: {err}", spec.id),
        };
        let mut style = self.renderer.style();
        if let Err(err) = style.add_source(source) {
            return error!("failed to add raster source {}: {err}", spec.id);
        }
        if let Err(err) = style.add_layer(layer) {
            error!("failed to add raster layer {}: {err}", spec.id);
        }
    }

    fn apply_geo_layer(&mut self, id: u32) {
        let Some(geo) = self.geo.get(&id) else { return };
        let source_id = geo_source_id(id);
        let data = match GeoJson::from_json_value(&feature_collection(&geo.features)) {
            Ok(data) => data,
            Err(err) => return error!("invalid GeoJSON for layer {id}: {err}"),
        };
        let mut source = GeoJsonSource::new(&source_id);
        source.set_geojson(&data);
        let layers = geo_layers_json(id, geo.kind);

        let mut style = self.renderer.style();
        if let Err(err) = style.add_source(source) {
            return error!("failed to add GeoJSON source {source_id}: {err}");
        }
        for layer in layers {
            match AnyLayer::from_json_value(&layer) {
                Ok(layer) => {
                    if let Err(err) = style.add_layer(layer) {
                        error!("failed to add layer for {source_id}: {err}");
                    }
                }
                Err(err) => error!("invalid layer for {source_id}: {err}"),
            }
        }
        self.needs_frame.store(true, Ordering::Release);
    }

    fn update_geo_source(&mut self, id: u32) {
        let Some(geo) = self.geo.get(&id) else { return };
        let data = match GeoJson::from_json_value(&feature_collection(&geo.features)) {
            Ok(data) => data,
            Err(err) => return error!("invalid GeoJSON for layer {id}: {err}"),
        };
        match self.renderer.style().source_mut(geo_source_id(id)) {
            Some(SourceRefMut::GeoJson(mut source)) => source.set_geojson(&data),
            _ => warn!("GeoJSON source for layer {id} is missing from the style"),
        }
        self.needs_frame.store(true, Ordering::Release);
    }

    /// Renders with MapLibre and keeps the resulting texture for presentation.
    fn render_frame(&mut self) {
        self.renderer.render_once();
        if let Some(texture) = self.renderer.take_texture() {
            self.pending_frame = Some(texture);
        }
    }

    /// Copies the pending MapLibre frame into the next free ring slot.
    fn present_pending(&mut self) {
        let (Some(source), Some(texture)) = (&self.pending_frame, &self.texture) else {
            return;
        };
        let mut frame = match texture.try_next_frame() {
            Ok(frame) => frame,
            // Flutter still holds every slot; retry on the next tick.
            Err(PluginError::Busy) => return,
            Err(err) => {
                self.pending_frame = None;
                return error!("failed to acquire texture frame: {err:?}");
            }
        };

        let source = source.clone();
        let rendered = frame.render(move |_device, encoder, view| {
            let target = view.texture();
            let (s, t) = (source.size(), target.size());
            encoder.copy_texture_to_texture(
                source.as_image_copy(),
                target.as_image_copy(),
                wgpu::Extent3d {
                    width: s.width.min(t.width),
                    height: s.height.min(t.height),
                    depth_or_array_layers: 1,
                },
            );
        });
        self.pending_frame = None;
        if let Err(err) = rendered.and_then(|()| frame.present()) {
            return error!("failed to present texture frame: {err:?}");
        }

        let viewport = self
            .camera
            .viewport(f64::from(self.size.width), f64::from(self.size.height));
        self.shared.frames.send_replace(Some(RenderedMapFrame {
            sequence: self.sequence.fetch_add(1, Ordering::Relaxed) + 1,
            viewport,
            map_size: self.size,
        }));
    }
}
