use std::sync::Arc;

use flutter_plugin_sdk::PixelBufferTexture;

use crate::api::dart_types::MapSize;
use crate::rust_shell::create_pixel_buffer_texture;

pub type SharedPixelTexture = Arc<PixelBufferTexture>;

/// Creates a shell-owned RGBA pixel buffer texture and returns its Flutter
/// texture registry identifier.
pub fn create_flutter_texture(size: MapSize) -> anyhow::Result<(SharedPixelTexture, i64)> {
    let (texture, texture_id) = create_pixel_buffer_texture(size)?;
    Ok((Arc::new(texture), texture_id))
}
