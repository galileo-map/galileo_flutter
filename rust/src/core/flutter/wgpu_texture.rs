use std::sync::Arc;

use flutter_plugin_sdk::WgpuTexture;

use crate::api::dart_types::MapSize;
use crate::rust_shell::create_wgpu_texture;

pub type SharedWgpuTexture = Arc<WgpuTexture>;

/// Creates a shell-owned native wgpu texture ring and returns its Flutter
/// texture registry identifier.
///
/// Galileo records its map rendering directly into one of the ring's texture
/// slots, so no CPU pixel buffer is involved.
pub fn create_flutter_texture(size: MapSize) -> anyhow::Result<(SharedWgpuTexture, i64)> {
    let (texture, texture_id) = create_wgpu_texture(size)?;
    Ok((Arc::new(texture), texture_id))
}
