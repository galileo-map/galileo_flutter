//! Main API for Galileo Flutter integration with texture rendering.
//!
//! This module provides the interface between Dart and Rust for
//! managing Galileo maps in Flutter applications with real texture rendering.

use flutter_rust_bridge::frb;
use galileo::control::UserEventHandler;
use galileo::layer::data_provider::remove_parameters_modifier;
use galileo::layer::raster_tile_layer::RasterTileLayerBuilder;
use galileo::layer::vector_tile_layer::style::VectorTileStyle;
use galileo::layer::vector_tile_layer::VectorTileLayerBuilder;
use galileo::render::text::text_service::TextService;
use galileo::render::text::RustybuzzRasterizer;
use font_kit::source::SystemSource;
use font_kit::handle::Handle;
use galileo::tile_schema::TileSchemaBuilder;
use futures::future::join_all;
use log::{debug, info};
use std::sync::atomic::Ordering;

use crate::api::dart_types::*;
use crate::core::map_session::{MapSession, SessionID};
use crate::core::{init_logger, TOKIO_HANDLE,IS_INITIALIZED, SESSIONS, TILE_CACHE_PATH};

#[frb(init)]
pub fn init_galileo_flutter() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Initialize the Galileo Flutter plugin with FFI pointer for irondash
pub fn galileo_flutter_init(ffi_ptr: i64) {
    if IS_INITIALIZED.load(Ordering::SeqCst) {
        return;
    }

    // Initialize irondash FFI
    irondash_dart_ffi::irondash_init_ffi(ffi_ptr as *mut std::ffi::c_void);
    init_logger();
    initialize_font_service();
    info!("Galileo Flutter plugin initialized with FFI and texture support");
    IS_INITIALIZED.store(true, Ordering::SeqCst);
}

fn initialize_font_service(){
    let rasterizer: RustybuzzRasterizer = RustybuzzRasterizer::default();
    let _service: &'static TextService = TextService::initialize(rasterizer);
    if let Ok(default_font_source) = SystemSource::new().all_fonts(){
        for font_source in default_font_source {
            match font_source {
                Handle::Path{path , ..}=>{
                    _service.load_fonts(path);
                }
                _=>{}
            }
        }
    }
    else{
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
    engine_handle: i64,
    config: MapInitConfig,
) -> anyhow::Result<CreateNewSessionResponse> {
    info!("create_new_map_session was called");
    TOKIO_HANDLE.get_or_init(|| tokio::runtime::Handle::current());
    let session = MapSession::new(engine_handle, config).await?;
    info!("New map session created with ID {}", session.session_id);
    Ok(CreateNewSessionResponse {
        session_id: session.session_id,
        texture_id: session.get_flutter_texture_id().unwrap(),
    })
}

/// Triggers a map update and re-render.
pub async fn request_map_redraw(session_id: SessionID) -> anyhow::Result<()> {
    let session = {
        SESSIONS.lock()
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

/// Destroys all streams for a given engine
pub async fn destroy_all_engine_sessions(engine_id: i64) {
    debug!("destroy_engine_streams called for engine {}", engine_id);

    // Find and remove all sessions for this engine
    let session_ids: Vec<_> = SESSIONS.lock()
        .iter()
        .filter(|(_, s)| s.engine_handle == engine_id)
        .map(|(id, _)| *id)
        .collect();
    join_all(session_ids.into_iter().map(destroy_session)).await;
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

    if let Some(ctx) = flctx {
        crate::utils::invoke_on_platform_main_thread(move || {
            drop(ctx);
        });
    }

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
pub async fn add_session_layer(session_id: SessionID, layer_config: LayerConfig) -> anyhow::Result<()> {
    let session = {
        SESSIONS.lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone() 
    };

    match layer_config {
        LayerConfig::Osm => {
            let layer = RasterTileLayerBuilder::new_osm()
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to create OSM layer: {}", e))?;
            session.add_layer(layer).await;
        }
        LayerConfig::RasterTiles {
            url_template: _,
            attribution: _,
        } => {
            // For now, just return OSM layer for custom tile providers
            // TODO: Implement custom URL tile providers
            let layer = RasterTileLayerBuilder::new_osm()
                .build()
                .map_err(|e| anyhow::anyhow!("Failed to create OSM layer: {}", e))?;
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
    }

    Ok(())
}

pub async fn get_map_viewport(session_id: SessionID) -> Option<MapViewport> {
    let session = {
        SESSIONS.lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id)).ok()?
            .clone()
    };
    return session.get_viewport().await;
}

pub fn handle_event_for_session(session_id: SessionID, event: UserEvent) {
    let galileo_event = event.to_galileo();
    let session = SESSIONS.lock().get(&session_id).cloned();

    if let Some(session) = session {
        if let Some(handle) = TOKIO_HANDLE.get() {
            handle.spawn(async move {
                match session.map.try_lock() {
                    Ok(mut map) =>{session.controller.handle(&galileo_event, &mut map);},
                    Err(_) => info!("Map busy: {:?}", galileo_event),
                }
            });
        }
    }
}

pub async fn resize_session(session_id: SessionID, new_size: MapSize) -> anyhow::Result<()> {

    let session = {
        SESSIONS.lock()
            .get(&session_id)
            .ok_or_else(|| anyhow::anyhow!("Session {} not found", session_id))?
            .clone() 
    };

    session.resize(new_size).await
}
