use std::{
    sync::{mpsc, OnceLock},
    time::Duration,
};

use flutter_plugin_sdk::{
    FlutterRustPlugin, GpuTextures, MainThreadDispatcher, PluginError, PluginRegistrar,
    TextureDescriptor, TextureFormat, WgpuTexture,
};

use crate::api::dart_types::MapSize;

static GPU_TEXTURES: OnceLock<GpuTextures> = OnceLock::new();
static MAIN_THREAD_DISPATCHER: OnceLock<MainThreadDispatcher> = OnceLock::new();

struct GalileoRustShellPlugin;

impl FlutterRustPlugin for GalileoRustShellPlugin {
    fn register(&self, registrar: &mut PluginRegistrar) -> Result<(), PluginError> {
        let textures = registrar.gpu()?.clone();
        GPU_TEXTURES
            .set(textures)
            .map_err(|_| PluginError::Unsupported)?;
        MAIN_THREAD_DISPATCHER
            .set(registrar.main_thread_dispatcher().clone())
            .map_err(|_| PluginError::Unsupported)?;
        Ok(())
    }
}

pub fn register_application(registrar: &mut PluginRegistrar) -> Result<(), PluginError> {
    GalileoRustShellPlugin.register(registrar)
}

pub(crate) fn create_wgpu_texture(size: MapSize) -> anyhow::Result<(WgpuTexture, i64)> {
    let textures = GPU_TEXTURES
        .get()
        .ok_or_else(|| anyhow::anyhow!("Rust shell plugin was not registered"))?;
    let dispatcher = MAIN_THREAD_DISPATCHER
        .get()
        .ok_or_else(|| anyhow::anyhow!("Rust shell dispatcher was not registered"))?;
    let textures = textures.clone();
    let (sender, receiver) = mpsc::sync_channel(1);
    dispatcher
        .dispatch(move || {
            let result = textures
                .create_texture(TextureDescriptor {
                    width: size.width,
                    height: size.height,
                    format: TextureFormat::Rgba8Unorm,
                })
                .map(|texture| {
                    let texture_id = texture.texture_id();
                    (texture, texture_id)
                })
                .map_err(|error| anyhow::anyhow!("failed to create Rust shell texture: {error:?}"));
            let _ = sender.send(result);
        })
        .map_err(|error| {
            anyhow::anyhow!("failed to dispatch Rust shell texture creation: {error:?}")
        })?;
    receiver
        .recv_timeout(Duration::from_secs(5))
        .map_err(|error| anyhow::anyhow!("timed out creating Rust shell texture: {error}"))?
}

/// The shell's GPU capability, for code that renders on its own thread.
pub(crate) fn gpu_textures() -> anyhow::Result<GpuTextures> {
    GPU_TEXTURES
        .get()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("Rust shell plugin was not registered"))
}
