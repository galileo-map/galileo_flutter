//! Main API for Galileo Flutter integration with texture rendering.
//!
//! This module provides the interface between Dart and Rust for
//! managing Galileo maps in Flutter applications with real texture rendering.

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use font_kit::handle::Handle;
use font_kit::source::SystemSource;
use galileo::control::UserEventHandler;
use galileo::galileo_types::geo::Crs;
use galileo::layer::data_provider::remove_parameters_modifier;
use galileo::layer::feature_layer::FeatureLayer;
use galileo::layer::raster_tile_layer::RasterTileLayerBuilder;
use galileo::layer::vector_tile_layer::style::VectorTileStyle;
use galileo::layer::vector_tile_layer::VectorTileLayerBuilder;
use galileo::render::text::text_service::TextService;
use galileo::render::text::RustybuzzRasterizer;
use galileo::tile_schema::TileSchemaBuilder;
use log::{debug, info};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use crate::api::dart_types::*;
use crate::core::map_session::{MapSession, SessionID};
use crate::core::{init_logger, IS_INITIALIZED, SESSIONS, TILE_CACHE_PATH, TOKIO_HANDLE};

#[frb(init)]
pub fn init_galileo_flutter() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Initialize the Galileo Flutter plugin runtime.
pub fn galileo_flutter_init(_ffi_ptr: i64) {
    if IS_INITIALIZED.load(Ordering::SeqCst) {
        return;
    }

    init_logger();
    initialize_font_service();
    info!("Galileo Flutter plugin initialized with texture support");
    IS_INITIALIZED.store(true, Ordering::SeqCst);
}

fn initialize_font_service() {
    let rasterizer: RustybuzzRasterizer = RustybuzzRasterizer::default();
    let _service: &'static TextService = TextService::initialize(rasterizer);
    if let Ok(default_font_source) = SystemSource::new().all_fonts() {
        for font_source in default_font_source {
            match font_source {
                Handle::Path { path, .. } => {
                    _service.load_fonts(path);
                }
                Handle::Memory { bytes, .. } => {
                    _service.load_font(bytes);
                }
            }
        }
    } else {
        info!("Failed to find source!");
    }
}

pub fn set_tile_cache_path(path: Option<String>) {
    let mut cache_path = TILE_CACHE_PATH.write();
    *cache_path = path;
    if let Some(ref p) = *cache_path {
        info!("Tile cache path: {}", p);
    } else {
        info!("Tile caching disabled (no path set)");
    }
}

#[derive(Clone, Debug)]
pub struct CreateNewSessionResponse {
    pub session_id: u32,
    pub texture_id: i64,
}

pub async fn create_new_map_session(
    config: MapInitConfig,
) -> anyhow::Result<CreateNewSessionResponse> {
    info!("create_new_map_session was called");
    TOKIO_HANDLE.get_or_init(|| tokio::runtime::Handle::current());
    let session = MapSession::new(config).await?;
    info!("New map session created with ID {}", session.session_id);
    Ok(CreateNewSessionResponse {
        session_id: session.session_id,
        texture_id: session.get_flutter_texture_id().unwrap(),
    })
}

/// Triggers a map update and re-render.
pub async fn request_map_redraw(session_id: SessionID) -> anyhow::Result<()> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };

    session.redraw().await
}

/// Marks the session as alive (called periodically from Flutter)
pub fn mark_session_alive(session_id: SessionID) {
    if let Some(session) = SESSIONS.lock().get(&session_id) {
        session.mark_alive();
        debug!("Session {} marked as alive", session_id);
    }
}

/// Destroys a specific session
pub async fn destroy_session(session_id: SessionID) {
    debug!("destroy_session called for session {}", session_id);

    let session = match SESSIONS.lock().remove(&session_id) {
        Some(s) => s,
        None => {
            info!("Session {session_id} does not exist");
            return;
        }
    };

    let flctx = session.terminate().await;
    drop(flctx);

    info!("Session {} destroyed with full cleanup", session_id);
}

/// Replaces {z}, {x}, {y} with tile indices
fn create_url_source(url_template: String) -> impl Fn(&galileo::tile_schema::TileIndex) -> String {
    move |index: &galileo::tile_schema::TileIndex| {
        url_template
            .replace("{z}", &index.z.to_string())
            .replace("{x}", &index.x.to_string())
            .replace("{y}", &index.y.to_string())
    }
}

/// Adds a layer to a session
pub async fn add_session_layer(
    session_id: SessionID,
    layer_config: LayerConfig,
) -> anyhow::Result<()> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };

    match layer_config {
        LayerConfig::Osm => {
            let mut builder = RasterTileLayerBuilder::new_osm();

            if let Some(ref path) = *TILE_CACHE_PATH.read() {
                builder = builder
                    .with_file_cache_modifier_checked(path, Box::new(remove_parameters_modifier));
            }

            let mut layer = builder
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to create OSM layer: {}", e))?;
            // Tiles appear instantly; the default 300ms fade-in re-requests a
            // redraw from every frame while any tile is fading, which keeps
            // the render loop running at full rate on an otherwise static map.
            layer.set_fade_in_duration(Duration::ZERO);
            let layer = Arc::new(parking_lot::RwLock::new(layer));
            session.add_layer(layer).await;
        }
        LayerConfig::RasterTiles {
            url_template,
            attribution,
        } => {
            let tile_schema = TileSchemaBuilder::web_mercator(0..=22)
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to build raster tile schema: {}", e))?;

            let mut builder = RasterTileLayerBuilder::new_rest(create_url_source(url_template))
                .with_tile_schema(tile_schema);

            if let Some(ref path) = *TILE_CACHE_PATH.read() {
                builder = builder
                    .with_file_cache_modifier_checked(path, Box::new(remove_parameters_modifier));
            }

            if let Some(attr) = attribution {
                builder = builder.with_attribution(attr, "".to_string());
            }

            let mut layer = builder
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to create raster tile layer: {}", e))?;
            layer.set_fade_in_duration(Duration::ZERO);
            let layer = Arc::new(parking_lot::RwLock::new(layer));
            session.add_layer(layer).await;
        }
        LayerConfig::VectorTiles {
            url_template,
            style_json,
            attribution,
        } => {
            let style: VectorTileStyle = serde_json::from_str(&style_json)
                .map_err(|e| anyhow::anyhow!("Failed to parse vector tile style: {}", e))?;
            let tile_schema = TileSchemaBuilder::web_mercator(0..19)
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to build tile schema: {}", e))?;

            let mut builder = VectorTileLayerBuilder::new_rest(create_url_source(url_template))
                .with_style(style)
                .with_tile_schema(tile_schema);

            if let Some(ref path) = *TILE_CACHE_PATH.read() {
                builder = builder
                    .with_file_cache_modifier_checked(path, Box::new(remove_parameters_modifier));
            }

            if let Some(attr) = attribution {
                builder = builder.with_attribution(attr, "".to_string());
            }

            let layer = builder
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to create vector tile layer: {}", e))?;
            session.add_layer(layer).await;
        }
        LayerConfig::PolygonLayer { features } => {
            // PolygonSymbol is stateless; style is read per-feature at render time.
            let layer = FeatureLayer::new(features, PolygonSymbol {}, Crs::EPSG3857);
            session.add_layer(layer).await;
        }

        LayerConfig::PointLayer { features } => {
            let layer = FeatureLayer::new(features, PointSymbol {}, Crs::EPSG3857);
            session.add_layer(layer).await;
        }
        LayerConfig::WidgetLayer => {
            // Handled by flutter
        }
    }

    Ok(())
}

pub async fn add_point_feature_layer(
    session_id: SessionID,
    initial_points: Vec<Point>,
) -> anyhow::Result<u32> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };

    let layer = FeatureLayer::new(initial_points, PointSymbol {}, Crs::EPSG3857);
    let layer_id = session.add_managed_layer(layer).await;
    Ok(layer_id)
}

pub async fn add_polygon_feature_layer(
    session_id: SessionID,
    initial_polygons: Vec<Polygon>,
) -> anyhow::Result<u32> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };

    let layer = FeatureLayer::new(initial_polygons, PolygonSymbol {}, Crs::EPSG3857);
    let layer_id = session.add_managed_layer(layer).await;
    Ok(layer_id)
}

pub async fn add_point_to_layer(
    session_id: SessionID,
    layer_id: u32,
    point: Point,
) -> anyhow::Result<u32> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };
    let feature_id = session.add_point_to_layer(layer_id, point).await?;
    Ok(unsafe {
        u32::try_from(std::mem::transmute::<galileo::layer::FeatureId, u64>(
            feature_id,
        ))?
    })
}

pub async fn add_polygon_to_layer(
    session_id: SessionID,
    layer_id: u32,
    polygon: Polygon,
) -> anyhow::Result<u32> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };
    let feature_id = session.add_polygon_to_layer(layer_id, polygon).await?;
    unsafe {
        u32::try_from(std::mem::transmute::<galileo::layer::FeatureId, u64>(
            feature_id,
        ))
        .map_err(|e| e.into())
    }
}

pub async fn remove_point_from_layer(
    session_id: SessionID,
    layer_id: u32,
    index: u32,
) -> anyhow::Result<bool> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };
    let id = unsafe { std::mem::transmute::<u64, galileo::layer::FeatureId>(u64::from(index)) };
    session.remove_point_from_layer(layer_id, id).await
}

pub async fn remove_polygon_from_layer(
    session_id: SessionID,
    layer_id: u32,
    index: u32,
) -> anyhow::Result<bool> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };
    let id = unsafe { std::mem::transmute::<u64, galileo::layer::FeatureId>(u64::from(index)) };
    session.remove_polygon_from_layer(layer_id, id).await
}

pub async fn get_map_viewport(session_id: SessionID) -> Option<MapViewport> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))
            .ok()?
            .clone()
    };
    return session.get_viewport().await;
}

/// Emits the viewport used for each completed texture render.
///
/// The underlying watch channel keeps only the newest frame so Flutter cannot
/// build up stale overlay updates while the map is moving.
pub async fn stream_rendered_map_frames(
    session_id: SessionID,
    sink: StreamSink<RenderedMapFrame>,
) -> anyhow::Result<()> {
    let session = SESSIONS
        .lock()
        .get(&session_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?;
    let mut frames = session.subscribe_rendered_frames();
    drop(session);

    if let Some(frame) = frames.borrow_and_update().as_ref().copied() {
        if sink.add(frame).is_err() {
            return Ok(());
        }
    }

    while frames.changed().await.is_ok() {
        if let Some(frame) = frames.borrow_and_update().as_ref().copied() {
            if sink.add(frame).is_err() {
                break;
            }
        }
    }
    Ok(())
}

pub async fn handle_event_for_session(session_id: SessionID, event: UserEvent) {
    let galileo_event = event.to_galileo();
    let session = SESSIONS.lock().get(&session_id).cloned();

    if let Some(session) = session {
        let mut map = session.map.lock().await;
        session.controller.handle(&galileo_event, &mut map);
    }
}

pub async fn resize_session(session_id: SessionID, new_size: MapSize) -> anyhow::Result<i64> {
    let session = {
        SESSIONS
            .lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone()
    };

    session.resize(new_size).await
}
