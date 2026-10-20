use flutter_plugin_sdk::gpu::wgpu::{CommandEncoder, Device, TextureView};
use galileo::galileo_types::cartesian::Size;
use galileo::render::WgpuRenderer;
use galileo::Map;
use log::debug;

/// Windowless Galileo renderer that draws into texture views owned by the
/// Flutter Rust shell.
///
/// Galileo's renderer owns no wgpu device of its own: it is created lazily on
/// the shell's device (the device that owns the target texture), and every
/// frame records its commands into the encoder handed to it by the shell.
/// The map therefore reaches Flutter as native GPU textures with no CPU pixel
/// buffer in between.
pub struct WindowlessRenderer {
    galileo_renderer: Option<WgpuRenderer>,
    size: Size<u32>,
}

impl WindowlessRenderer {
    pub fn new(size: Size<u32>) -> Self {
        Self {
            galileo_renderer: None,
            size,
        }
    }

    /// Resizes the renderer and recreates its internal multisample and
    /// stencil textures.
    pub fn resize(&mut self, new_size: Size<u32>) {
        self.size = new_size;
        if let Some(renderer) = &mut self.galileo_renderer {
            renderer.resize(new_size);
        }
    }

    /// Gets the current size of the renderer.
    pub fn size(&self) -> Size<u32> {
        self.size
    }

    /// Records a Galileo map render into `encoder`, resolving into `view`.
    ///
    /// `device` must own both `encoder` and `view`. The renderer is
    /// initialized on the first call and then reused for subsequent frames.
    pub fn render(
        &mut self,
        map: &Map,
        device: &Device,
        encoder: &mut CommandEncoder,
        view: &TextureView,
    ) {
        let target_extent = view.texture().size();
        let target_size = Size::new(target_extent.width, target_extent.height);
        if self.size != target_size {
            self.size = target_size;
            if let Some(renderer) = &mut self.galileo_renderer {
                renderer.resize(target_size);
            }
        }

        if self.galileo_renderer.is_none() {
            debug!("Initializing Galileo renderer on the Rust shell GPU device");
            self.galileo_renderer = Some(WgpuRenderer::new_with_device(device.clone(), self.size));
        }

        let renderer = self
            .galileo_renderer
            .as_mut()
            .expect("renderer initialized above");
        renderer.trim_textures();
        renderer.render_to_texture_view_with_encoder(map, view, encoder);
    }
}

impl std::fmt::Debug for WindowlessRenderer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WindowlessRenderer")
            .field("size", &self.size)
            .field("initialized", &self.galileo_renderer.is_some())
            .finish()
    }
}
