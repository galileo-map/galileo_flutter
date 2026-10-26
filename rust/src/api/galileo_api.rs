//! Main API for Galileo Flutter integration with texture rendering.
//!
//! This module provides the interface between Dart and Rust for
//! managing Galileo maps in Flutter applications with real texture rendering.

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use log::{debug, info};
use std::sync::atomic::Ordering;

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
    info!("Galileo Flutter plugin initialized with texture support");
    IS_INITIALIZED.store(true, Ordering::SeqCst);
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

    let textures = session.terminate().await;
    drop(textures);

    info!("Session {} destroyed with full cleanup", session_id);
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

    session.add_layer(layer_config).await
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

    session.add_point_layer(&initial_points).await
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

    session.add_polygon_layer(&initial_polygons).await
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
    session.add_point_to_layer(layer_id, point).await
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
    session.add_polygon_to_layer(layer_id, polygon).await
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
    session.remove_point_from_layer(layer_id, index).await
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
    session.remove_polygon_from_layer(layer_id, index).await
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
    let session = SESSIONS.lock().get(&session_id).cloned();

    if let Some(session) = session {
        session.handle_event(event);
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
