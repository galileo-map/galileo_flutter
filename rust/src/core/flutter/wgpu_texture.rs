use flutter_plugin_sdk::WgpuTexture;

use crate::api::dart_types::MapSize;
use crate::rust_shell::create_wgpu_texture;

/// Creates a shell-owned native wgpu texture ring and returns its Flutter
/// texture registry identifier.
///
/// MapLibre renders on the shell's GPU device and each finished frame is
/// copied into one of the ring's slots on the GPU.
pub fn create_flutter_texture(size: MapSize) -> anyhow::Result<(WgpuTexture, i64)> {
    create_wgpu_texture(size)
}
