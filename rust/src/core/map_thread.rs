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
use flutter_plugin_sdk::{GpuQueue, PluginError, WgpuTexture, WgpuTextureFrame};
use log::{debug, error, info, warn};
use maplibre_native::{
    AnyLayer, AnySource, CameraState, CameraUpdate, Continuous, GeoJson, GeoJsonSource,
    ImageRenderer, ImageRendererBuilder, LatLng, QueueOps, ResourceOptions, RunLoopHandle,
    ScreenCoordinate, Size, SourceRefMut,
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
/// Duration of MapLibre Native's anchored zoom transition.
const ZOOM_DURATION: Duration = Duration::from_millis(220);
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
    /// Flutter acquired the queued texture; render the next camera position now.
    FrameAcquired,
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
        let frame_wake = tx.clone();
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        std::thread::Builder::new()
            .name("maplibre-map".into())
            .spawn(move || match MapState::new(config, texture, shared) {
                Ok(state) => {
                    let _ = ready_tx.send(Ok(()));
                    state.run(rx, frame_wake);
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
    camera_dirty: bool,
    size: MapSize,
    texture: Option<WgpuTexture>,
    retired: Option<WgpuTexture>,
    /// Invalidates callbacks from texture slots retired by a resize.
    frame_epoch: Arc<AtomicU64>,
    /// At most one frame may wait in Flutter's FIFO texture queue.
    queued_frame: Arc<AtomicBool>,
    frame_wake: Option<mpsc::Sender<Command>>,
    acquired_frames: Arc<AtomicU64>,
    stats: Option<FrameStats>,
    sequence: AtomicU64,
    zoom_target: Option<f64>,
    native_animation_until: Option<Instant>,
    drag: DragTracker,
}

/// Smoothed velocity of the current drag, for flinging on release.
struct DragTracker {
    last_event_micros: Option<u64>,
    last_received: Option<Instant>,
    velocity: (f64, f64),
}

struct FrameStats {
    since: Instant,
    rendered: u64,
    busy: u64,
    render_micros: u128,
    slowest_micros: u128,
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
            camera_dirty: false,
            size: config.size,
            texture: Some(texture),
            retired: None,
            frame_epoch: Arc::new(AtomicU64::new(0)),
            queued_frame: Arc::new(AtomicBool::new(false)),
            frame_wake: None,
            acquired_frames: Arc::new(AtomicU64::new(0)),
            stats: std::env::var_os("GALILEO_FRAME_STATS").map(|_| FrameStats {
                since: Instant::now(),
                rendered: 0,
                busy: 0,
                render_micros: 0,
                slowest_micros: 0,
            }),
            sequence: AtomicU64::new(0),
            zoom_target: None,
            native_animation_until: None,
            drag: DragTracker {
                last_event_micros: None,
                last_received: None,
                velocity: (0.0, 0.0),
            },
        };
        state.reload_style();
        Ok(state)
    }

    fn run(mut self, rx: mpsc::Receiver<Command>, frame_wake: mpsc::Sender<Command>) {
        self.frame_wake = Some(frame_wake);
        let run_loop = RunLoopHandle::current();
        let mut last_activity = Instant::now();
        let mut next_frame_at = Instant::now();
        'outer: loop {
            let mut frame_acquired = false;
            let tick = if last_activity.elapsed() > IDLE_AFTER {
                IDLE_TICK
            } else {
                ACTIVE_TICK
            };
            match rx.recv_timeout(next_frame_at.saturating_duration_since(Instant::now())) {
                Ok(command) => {
                    last_activity = Instant::now();
                    frame_acquired |= matches!(command, Command::FrameAcquired);
                    if !self.handle(command) {
                        break 'outer;
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
            // Bound the drain so a high-polling mouse cannot postpone rendering
            // indefinitely. The camera update below coalesces drag bursts.
            for _ in 0..128 {
                let Ok(command) = rx.try_recv() else { break };
                last_activity = Instant::now();
                frame_acquired |= matches!(command, Command::FrameAcquired);
                if !self.handle(command) {
                    break 'outer;
                }
            }

            run_loop.tick();
            if !frame_acquired && Instant::now() < next_frame_at {
                continue;
            }
            if self.camera_dirty {
                self.apply_camera();
            }
            if self.animate() {
                last_activity = Instant::now();
            }
            if self.needs_frame.load(Ordering::Acquire) {
                last_activity = Instant::now();
                self.render_frame();
            }
            self.report_frame_stats();
            next_frame_at = if frame_acquired {
                Instant::now() + tick
            } else {
                (next_frame_at + tick).max(Instant::now())
            };
        }
        debug!("map thread exiting");
    }

    /// Returns `false` when the thread should stop.
    fn handle(&mut self, command: Command) -> bool {
        match command {
            Command::SetBaseStyle(style) => {
                self.stop_native_animation();
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
            Command::FrameAcquired => {}
            Command::Resize {
                texture,
                size,
                done,
            } => {
                self.stop_native_animation();
                self.size = size;
                self.renderer.set_map_size(Size {
                    width: size.width.max(1),
                    height: size.height.max(1),
                });
                self.retired = self.texture.replace(texture);
                self.frame_epoch.fetch_add(1, Ordering::AcqRel);
                self.queued_frame = Arc::new(AtomicBool::new(false));
                self.apply_camera();
                // The new texture must hold a frame before Flutter switches to it.
                let deadline = Instant::now() + Duration::from_millis(250);
                while !self.render_frame() && Instant::now() < deadline {
                    std::thread::sleep(Duration::from_millis(4));
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
            UserEvent::ButtonPressed(MouseButton::Left, event) => {
                // Direct manipulation takes ownership of the camera.
                self.stop_native_animation();
                self.drag.last_event_micros =
                    (event.timestamp_micros != 0).then_some(event.timestamp_micros);
                self.drag.last_received = None;
                self.drag.velocity = (0.0, 0.0);
            }
            UserEvent::Drag(MouseButton::Left, delta, event) => {
                let (w, h) = self.screen_size();
                let p = event.screen_pointer_position;
                self.stop_native_animation();
                self.track_drag(delta.dx, delta.dy, event.timestamp_micros);
                self.camera.pan(delta.dx, delta.dy, p.x, p.y, w, h);
                self.camera_dirty = true;
            }
            UserEvent::Rotate(degrees, anchor) => {
                let (w, h) = self.screen_size();
                self.stop_native_animation();
                self.camera.rotate_by(degrees, anchor.x, anchor.y, w, h);
                self.apply_camera();
            }
            UserEvent::Pitch(degrees) => {
                self.stop_native_animation();
                self.camera.pitch_by(degrees);
                self.apply_camera();
            }
            UserEvent::ButtonReleased(MouseButton::Left, event)
            | UserEvent::DragEnded(MouseButton::Left, event) => {
                self.release_drag(event.timestamp_micros)
            }
            UserEvent::ZoomAnimated(factor, point) => self.request_zoom(factor, point.x, point.y),
            UserEvent::ZoomImmediate(factor, point) => {
                if factor.is_finite() && factor > 0.0 {
                    self.stop_native_animation();
                    let (w, h) = self.screen_size();
                    self.camera
                        .zoom_by_resolution(factor, point.x, point.y, w, h);
                    self.apply_camera();
                }
            }
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

    fn track_drag(&mut self, dx: f64, dy: f64, timestamp_micros: u64) {
        let now = Instant::now();
        let instant = match self.drag.last_event_micros {
            Some(last)
                if timestamp_micros > last
                    && timestamp_micros - last < FLING_MAX_IDLE.as_micros() as u64 =>
            {
                let dt = (timestamp_micros - last) as f64 / 1_000_000.0;
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
        self.drag.last_event_micros = (timestamp_micros != 0).then_some(timestamp_micros);
        self.drag.last_received = Some(now);
    }

    fn release_drag(&mut self, timestamp_micros: u64) {
        let recent = match self.drag.last_event_micros {
            Some(last) if timestamp_micros >= last => {
                timestamp_micros - last < FLING_MAX_IDLE.as_micros() as u64
            }
            _ => self
                .drag
                .last_received
                .is_some_and(|last| last.elapsed() < FLING_MAX_IDLE),
        };
        self.drag.last_received = None;
        self.drag.last_event_micros = None;
        let (vx, vy) = std::mem::take(&mut self.drag.velocity);
        if recent && vx.hypot(vy) >= FLING_MIN_SPEED {
            if self.camera_dirty {
                self.apply_camera();
            }
            let duration_secs =
                (FLING_TAU * (vx.hypot(vy) / FLING_STOP_SPEED).ln()).clamp(0.15, 1.2);
            let distance_factor = FLING_TAU * (1.0 - (-duration_secs / FLING_TAU).exp());
            let (w, h) = self.screen_size();
            let mut target = self.camera;
            target.pan(
                vx * distance_factor,
                vy * distance_factor,
                w / 2.0,
                h / 2.0,
                w,
                h,
            );
            let center = target.center();
            self.renderer.ease_camera(
                &CameraUpdate::new().center(LatLng {
                    lat: center.latitude,
                    lng: center.longitude,
                }),
                Duration::from_secs_f64(duration_secs),
            );
            self.native_animation_until =
                Some(Instant::now() + Duration::from_secs_f64(duration_secs));
            self.needs_frame.store(true, Ordering::Release);
        }
    }

    /// Ask MapLibre Native to animate the zoom around a screen anchor.
    fn request_zoom(&mut self, factor: f64, px: f64, py: f64) {
        if !factor.is_finite() || factor <= 0.0 {
            return;
        }
        let base = self.zoom_target.unwrap_or(self.camera.zoom);
        self.stop_native_animation();
        let zoom = (base - factor.log2())
            .clamp(crate::core::camera::MIN_ZOOM, crate::core::camera::MAX_ZOOM);
        self.renderer.ease_camera(
            &CameraUpdate::new()
                .zoom(zoom)
                .anchor(ScreenCoordinate { x: px, y: py }),
            ZOOM_DURATION,
        );
        self.zoom_target = Some(zoom);
        self.native_animation_until = Some(Instant::now() + ZOOM_DURATION);
        self.needs_frame.store(true, Ordering::Release);
    }

    /// Keep rendering while MapLibre Native advances its camera transition.
    fn animate(&mut self) -> bool {
        let Some(until) = self.native_animation_until else {
            return false;
        };
        self.needs_frame.store(true, Ordering::Release);
        if Instant::now() >= until {
            self.native_animation_until = None;
            self.zoom_target = None;
            return false;
        }
        true
    }

    fn stop_native_animation(&mut self) {
        if self.native_animation_until.take().is_some() {
            self.renderer.cancel_camera_transition();
            self.sync_camera_from_renderer();
        }
        self.zoom_target = None;
    }

    fn sync_camera_from_renderer(&mut self) {
        let Some(state) = self.renderer.camera_state() else {
            return;
        };
        self.camera = Self::camera_from_native(state);
    }

    fn camera_from_native(state: CameraState) -> Camera {
        let mut camera = Camera::new(
            GeoLocation {
                latitude: state.center.lat,
                longitude: state.center.lng,
            },
            state.zoom,
        );
        camera.bearing = state.bearing;
        camera.pitch = state.pitch;
        camera
    }

    fn apply_camera(&mut self) {
        self.camera_dirty = false;
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

    /// Reserve a display slot before rendering so a full ring cannot make us
    /// generate and discard GPU textures. Leave the request set while busy;
    /// the next available slot will receive the latest camera state.
    fn render_frame(&mut self) -> bool {
        // Flutter consumes ready frames oldest-first. Rendering a second frame
        // before it acquires the first only makes gestures display stale views.
        if self.queued_frame.load(Ordering::Acquire) {
            if let Some(stats) = &mut self.stats {
                stats.busy += 1;
            }
            return false;
        }
        let Some(texture) = &self.texture else {
            return true;
        };
        let frame = match texture.try_next_frame() {
            Ok(frame) => frame,
            Err(PluginError::Busy) => {
                if let Some(stats) = &mut self.stats {
                    stats.busy += 1;
                }
                return false;
            }
            Err(err) => {
                error!("failed to acquire texture frame: {err:?}");
                return true;
            }
        };
        self.needs_frame.swap(false, Ordering::AcqRel);
        let started = Instant::now();
        self.renderer.render_once();
        // MapLibre may advance a transition while finishing the render. Use
        // its pre-render snapshot for this texture, then read its current
        // camera separately so the next gesture starts at the right position.
        let rendered_camera = self
            .renderer
            .rendered_camera_state()
            .map(Self::camera_from_native)
            .unwrap_or(self.camera);
        let viewport =
            rendered_camera.viewport(f64::from(self.size.width), f64::from(self.size.height));
        self.sync_camera_from_renderer();
        *self.shared.viewport.lock() = Some(viewport);
        if let Some(stats) = &mut self.stats {
            let micros = started.elapsed().as_micros();
            stats.rendered += 1;
            stats.render_micros += micros;
            stats.slowest_micros = stats.slowest_micros.max(micros);
        }
        let Some(source) = self.renderer.take_texture() else {
            return true;
        };
        let metadata = RenderedMapFrame {
            sequence: self.sequence.fetch_add(1, Ordering::Relaxed) + 1,
            viewport,
            map_size: self.size,
        };
        self.present_frame(frame, source, metadata);
        true
    }

    /// Copies the rendered MapLibre texture when Flutter acquires this slot.
    fn present_frame(
        &self,
        mut frame: WgpuTextureFrame,
        source: wgpu::Texture,
        metadata: RenderedMapFrame,
    ) {
        let frames = self.shared.frames.clone();
        let frame_epoch = self.frame_epoch.clone();
        let queued_frame = self.queued_frame.clone();
        let frame_wake = self.frame_wake.clone();
        let acquired_frames = self.acquired_frames.clone();
        let epoch = frame_epoch.load(Ordering::Acquire);
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
            // The shell executes this task when Flutter acquires this texture
            // slot. Keep the overlay viewport with the image it describes.
            queued_frame.store(false, Ordering::Release);
            if frame_epoch.load(Ordering::Acquire) == epoch {
                acquired_frames.fetch_add(1, Ordering::Relaxed);
                frames.send_replace(Some(metadata));
                if let Some(frame_wake) = &frame_wake {
                    let _ = frame_wake.send(Command::FrameAcquired);
                }
            }
        });
        if let Err(err) = rendered {
            error!("failed to record texture frame: {err:?}");
            return;
        }
        self.queued_frame.store(true, Ordering::Release);
        if let Err(err) = frame.present() {
            self.queued_frame.store(false, Ordering::Release);
            error!("failed to present texture frame: {err:?}");
        }
    }

    fn report_frame_stats(&mut self) {
        let Some(stats) = &mut self.stats else { return };
        if stats.since.elapsed() < Duration::from_secs(2) {
            return;
        }
        let avg_ms = if stats.rendered == 0 {
            0.0
        } else {
            stats.render_micros as f64 / stats.rendered as f64 / 1000.0
        };
        info!(
            "map frames: rendered={}, acquired={}, waiting_for_flutter={}, render_avg={avg_ms:.1}ms, render_max={:.1}ms",
            stats.rendered,
            self.acquired_frames.swap(0, Ordering::Relaxed),
            stats.busy,
            stats.slowest_micros as f64 / 1000.0,
        );
        *stats = FrameStats {
            since: Instant::now(),
            rendered: 0,
            busy: 0,
            render_micros: 0,
            slowest_micros: 0,
        };
    }
}
