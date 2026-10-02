use std::any::Any;
use std::cmp::Ordering;
use std::hash::{Hash, Hasher};
use std::mem::size_of;
use std::sync::{Arc, Weak};
use std::time::Duration;

use ahash::HashMap;
use flutter_plugin_sdk::gpu::wgpu;
use galileo_types::cartesian::{Rect, Size, Vector2};
use lyon::tessellation::VertexBuffers;
use nalgebra::{Point4, Rotation3, Vector3};
use parking_lot::Mutex;
use wgpu::util::DeviceExt;
use wgpu::{
    BindGroup, Buffer, CommandEncoder, Device, Extent3d, Origin3d,
    RenderPassDepthStencilAttachment, StoreOp, TexelCopyBufferInfo, TexelCopyBufferLayout,
    TexelCopyTextureInfo, Texture, TextureAspect, TextureDescriptor, TextureDimension,
    TextureFormat, TextureUsages, TextureView, TextureViewDescriptor,
};

use super::render_bundle::screen_set::{RenderSetState, ScreenSetData};
use super::{BundleToDraw, Canvas, PackedBundle, RenderOptions};
use crate::Color;
use crate::decoded_image::DecodedImage;
use crate::map::Map;
use crate::render::render_bundle::RenderBundle;
use crate::render::render_bundle::world_set::{PointInstance, PolyVertex, WorldRenderSet};
use crate::render::wgpu::pipelines::Pipelines;
use crate::render::wgpu::pipelines::image::WgpuImage;
use crate::view::MapView;

mod pipelines;

const DEFAULT_BACKGROUND: Color = Color::WHITE;
const DEPTH_FORMAT: TextureFormat = TextureFormat::Depth24PlusStencil8;
const TARGET_TEXTURE_FORMAT: TextureFormat = TextureFormat::Rgba8Unorm;

type TexturesMap = HashMap<u64, (Weak<DecodedImage>, Arc<BindGroup>)>;

/// A newly created image texture together with the staging buffer that carries
/// its pixels. The staging buffer is uploaded with an encoder copy before the
/// first render pass that samples the texture.
struct ImageUpload {
    texture: Texture,
    staging: Buffer,
    width: u32,
    height: u32,
    bytes_per_row: u32,
}

/// Render backend that uses `wgpu` crate to render the map.
pub struct WgpuRenderer {
    device: Device,
    renderer_targets: Option<RendererTargets>,
    background: Color,
    textures: Mutex<TexturesMap>,
}

struct RendererTargets {
    size: Size<u32>,
    pipelines: Pipelines,
    multisampling_view: TextureView,
    stencil_view_multisample: TextureView,
    stencil_view: TextureView,
}

impl WgpuRenderer {
    /// Creates a renderer that records map drawing into externally supplied
    /// wgpu command encoders.
    ///
    /// `device` must be the device that owns the target texture views passed
    /// to [`Self::render_to_texture_view`]. Every renderer resource is created
    /// on that device, so the map is drawn without any CPU pixel read-back.
    pub fn new_with_device(device: Device, size: Size<u32>) -> Self {
        let mut renderer = Self {
            device,
            renderer_targets: None,
            background: DEFAULT_BACKGROUND,
            textures: Default::default(),
        };
        renderer.init_targets(size);
        renderer
    }

    fn init_targets(&mut self, size: Size<u32>) {
        let multisampling_view =
            Self::create_multisample_texture(&self.device, size, TARGET_TEXTURE_FORMAT);
        let stencil_view_multisample = Self::create_stencil_texture(&self.device, size, 4);
        let stencil_view = Self::create_stencil_texture(&self.device, size, 1);
        let pipelines = Pipelines::create(&self.device, TARGET_TEXTURE_FORMAT);

        self.renderer_targets = Some(RendererTargets {
            size,
            pipelines,
            multisampling_view,
            stencil_view_multisample,
            stencil_view,
        });
    }

    /// Set the background color for the map.
    pub fn set_background(&mut self, color: Color) {
        self.background = color;
    }

    /// Returns `true` if the renderer can be used to draw to.
    pub fn initialized(&self) -> bool {
        self.renderer_targets.is_some()
    }

    fn create_multisample_texture(
        device: &Device,
        size: Size<u32>,
        format: TextureFormat,
    ) -> TextureView {
        let multisampling_texture = device.create_texture(&TextureDescriptor {
            label: Some("Multisampling texture"),
            size: Extent3d {
                width: size.width(),
                height: size.height(),
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 4,
            dimension: TextureDimension::D2,
            format,
            usage: TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        });

        multisampling_texture.create_view(&TextureViewDescriptor::default())
    }

    fn create_stencil_texture(device: &Device, size: Size<u32>, sample_count: u32) -> TextureView {
        let texture = device.create_texture(&TextureDescriptor {
            label: Some("Stencil/depth texture"),
            size: Extent3d {
                width: size.width(),
                height: size.height(),
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count,
            dimension: TextureDimension::D2,
            format: DEPTH_FORMAT,
            usage: TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        });

        texture.create_view(&TextureViewDescriptor::default())
    }

    /// Changes the size of the area the map is rendered into.
    ///
    /// This must be called before any render calls when the target texture
    /// changes size.
    pub fn resize(&mut self, new_size: Size<u32>) {
        let Some(renderer_targets) = &mut self.renderer_targets else {
            return;
        };

        if renderer_targets.size != new_size && new_size.width() > 0 && new_size.height() > 0 {
            renderer_targets.size = new_size;
            renderer_targets.multisampling_view =
                Self::create_multisample_texture(&self.device, new_size, TARGET_TEXTURE_FORMAT);
            renderer_targets.stencil_view_multisample =
                Self::create_stencil_texture(&self.device, new_size, 4);
            renderer_targets.stencil_view = Self::create_stencil_texture(&self.device, new_size, 1);
        }
    }

    /// Records the map render into `encoder`, resolving into `view`.
    pub fn render_to_texture_view(
        &self,
        map: &Map,
        view: &TextureView,
        encoder: &mut CommandEncoder,
    ) {
        let Some(renderer_targets) = &self.renderer_targets else {
            return;
        };

        {
            let background = self.background.to_f32_array();
            let _ = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &renderer_targets.multisampling_view,
                    depth_slice: None,
                    resolve_target: Some(view),
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: background[0] as f64,
                            g: background[1] as f64,
                            b: background[2] as f64,
                            a: background[3] as f64,
                        }),
                        store: StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
        }

        self.render_map(map, view, encoder);
    }

    fn render_map(&self, map: &Map, texture_view: &TextureView, encoder: &mut CommandEncoder) {
        let view = map.view();
        let Some(renderer_targets) = &self.renderer_targets else {
            return;
        };

        let Some(mut canvas) =
            WgpuCanvas::new(self, renderer_targets, texture_view, view.clone(), encoder)
        else {
            log::warn!("Layer cannot be rendered to the map view.");
            return;
        };

        for layer in map.layers().iter_visible() {
            layer.render(view, &mut canvas);
        }

        let needs_animation = canvas.draw_screen_sets();
        canvas.flush_pending_uploads();
        if needs_animation {
            map.redraw();
        }
    }

    /// Returns the size of the rendering area.
    pub fn size(&self) -> Size {
        let size = match &self.renderer_targets {
            Some(set) => set.size,
            None => Size::default(),
        };

        Size::new(size.width() as f64, size.height() as f64)
    }

    /// Deallocates all unneeded textures.
    ///
    /// A texture is considered unneeded if there are no references left to the
    /// underlying image.
    pub fn trim_textures(&self) {
        self.textures
            .lock()
            .retain(|_, (image_ref, _)| image_ref.strong_count() > 0);
    }

    fn get_or_create_image_texture(
        &self,
        image: &Arc<DecodedImage>,
        pending: &Mutex<Vec<ImageUpload>>,
    ) -> Arc<BindGroup> {
        let mut hasher = ahash::AHasher::default();
        image.hash(&mut hasher);
        let hash = hasher.finish();

        if let Some((_, texture)) = self.textures.lock().get(&hash) {
            return texture.clone();
        }

        let (texture, staging, bind_group, width, height, bytes_per_row) = self
            .renderer_targets
            .as_ref()
            .expect("trying to use pipelines of uninitialized renderer")
            .pipelines
            .create_image_texture(&self.device, image);

        pending.lock().push(ImageUpload {
            texture,
            staging,
            width,
            height,
            bytes_per_row,
        });

        self.textures
            .lock()
            .insert(hash, (Arc::downgrade(image), bind_group.clone()));

        bind_group
    }
}

struct WgpuCanvas<'a> {
    renderer: &'a WgpuRenderer,
    renderer_targets: &'a RendererTargets,
    view: &'a TextureView,
    encoder: &'a mut CommandEncoder,
    map_view: MapView,

    pending_uploads: Mutex<Vec<ImageUpload>>,
    screen_sets: Vec<(Arc<Mutex<WgpuScreenSet>>, f32, Vector2<f32>)>,
}

impl<'a> WgpuCanvas<'a> {
    fn new(
        renderer: &'a WgpuRenderer,
        renderer_targets: &'a RendererTargets,
        view: &'a TextureView,
        map_view: MapView,
        encoder: &'a mut CommandEncoder,
    ) -> Option<Self> {
        let rotation_mtx = Rotation3::new(Vector3::new(
            map_view.rotation_x(),
            0.0,
            -map_view.rotation_z(),
        ))
        .to_homogeneous();
        let staging = renderer
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Map view staging buffer"),
                usage: wgpu::BufferUsages::COPY_SRC,
                contents: bytemuck::cast_slice(&[ViewUniform {
                    view_proj: map_view.map_to_scene_mtx()?,
                    view_rotation: rotation_mtx.cast::<f32>().data.0,
                    inv_screen_size: [
                        1.0 / renderer.size().width() as f32,
                        1.0 / renderer.size().height() as f32,
                    ],
                    resolution: map_view.resolution() as f32,
                    _padding: [0.0; 1],
                }]),
            });
        encoder.copy_buffer_to_buffer(
            &staging,
            0,
            renderer_targets.pipelines.map_view_buffer(),
            0,
            size_of::<ViewUniform>() as u64,
        );

        Some(Self {
            renderer,
            renderer_targets,
            view,
            encoder,
            map_view,
            pending_uploads: Mutex::new(Vec::new()),
            screen_sets: vec![],
        })
    }

    fn flush_pending_uploads(&mut self) {
        let pending = std::mem::take(&mut *self.pending_uploads.lock());
        for upload in pending {
            self.encoder.copy_buffer_to_texture(
                TexelCopyBufferInfo {
                    buffer: &upload.staging,
                    layout: TexelCopyBufferLayout {
                        offset: 0,
                        bytes_per_row: Some(upload.bytes_per_row),
                        rows_per_image: Some(upload.height),
                    },
                },
                TexelCopyTextureInfo {
                    aspect: TextureAspect::All,
                    texture: &upload.texture,
                    mip_level: 0,
                    origin: Origin3d::ZERO,
                },
                Extent3d {
                    width: upload.width,
                    height: upload.height,
                    depth_or_array_layers: 1,
                },
            );
        }
    }
}

impl Canvas for WgpuCanvas<'_> {
    fn size(&self) -> Size {
        self.renderer.size()
    }

    fn pack_bundle(&self, bundle: &RenderBundle) -> Box<dyn PackedBundle> {
        Box::new(WgpuPackedBundle::new(
            bundle,
            self.renderer,
            self.renderer_targets,
            &self.pending_uploads,
        ))
    }

    fn draw_bundles(&mut self, bundles: &[super::BundleToDraw], options: RenderOptions) {
        if bundles.is_empty() {
            log::debug!("Requested drawing of 0 bundles");
            return;
        }

        self.flush_pending_uploads();
        let encoder = &mut *self.encoder;

        {
            let (view, resolve_target, depth_view) = if options.antialias {
                (
                    &self.renderer_targets.multisampling_view,
                    Some(self.view),
                    &self.renderer_targets.stencil_view_multisample,
                )
            } else {
                (self.view, None, &self.renderer_targets.stencil_view)
            };

            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view,
                    depth_slice: None,
                    resolve_target,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Load,
                        store: StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: Some(RenderPassDepthStencilAttachment {
                    view: depth_view,
                    depth_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(1.0),
                        store: StoreOp::Discard,
                    }),
                    stencil_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(0),
                        store: StoreOp::Discard,
                    }),
                }),
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });

            let display_instances: Vec<_> = bundles
                .iter()
                .map(
                    |BundleToDraw {
                         opacity, offset, ..
                     }| DisplayInstance {
                        opacity: *opacity,
                        offset: [offset.dx(), offset.dy(), 0.0],
                    },
                )
                .collect();

            let display_buffer =
                self.renderer
                    .device
                    .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: None,
                        usage: wgpu::BufferUsages::VERTEX,
                        contents: bytemuck::cast_slice(&display_instances),
                    });
            render_pass.set_vertex_buffer(1, display_buffer.slice(..));

            for (
                index,
                BundleToDraw {
                    bundle,
                    opacity,
                    offset,
                },
            ) in bundles.iter().enumerate()
            {
                if let Some(cast) = bundle.as_any().downcast_ref::<WgpuPackedBundle>() {
                    self.renderer_targets.pipelines.render(
                        &mut render_pass,
                        cast,
                        options,
                        index as u32,
                    );

                    for screen_set in &cast.screen_sets {
                        self.screen_sets
                            .push((screen_set.clone(), *opacity, *offset));
                    }
                }
            }
        }
    }

    fn draw_screen_sets(&mut self) -> bool {
        if self.screen_sets.is_empty() {
            return false;
        }

        let view = &self.map_view;
        let Some(transform) = view.map_to_scene_transform() else {
            // current view cannot be rendered to screen
            return false;
        };
        let size = view.size();

        self.flush_pending_uploads();
        let screen_sets = std::mem::take(&mut self.screen_sets);
        let mut sets: Vec<_> = screen_sets
            .iter()
            .filter_map(|(set, _, offset)| {
                let Some(locked) = set.try_lock() else {
                    // TODO: this means that the same tile is reused. We just wait for it to
                    // disappear from the map. This would result in some visual bugs, but not so
                    // critical as to be blocked by it ATM.
                    return None;
                };

                let projected_anchor = transform
                    * Point4::new(
                        locked.anchor_point[0] as f64 + offset.dx() as f64,
                        locked.anchor_point[1] as f64 + offset.dy() as f64,
                        locked.anchor_point[2] as f64,
                        1.0,
                    );
                let normalaized = projected_anchor / projected_anchor.w.abs();

                Some((locked, normalaized, offset))
            })
            .collect();
        sets.sort_by(|a, b| {
            let displayed_cmp = match (a.0.state.is_displayed(), b.0.state.is_displayed()) {
                (true, false) => Ordering::Less,
                (false, true) => Ordering::Greater,
                _ => Ordering::Equal,
            };

            displayed_cmp.then(
                a.1.z
                    .partial_cmp(&b.1.z)
                    .unwrap_or(std::cmp::Ordering::Equal),
            )
        });

        let now = web_time::Instant::now();
        let mut displayed: Vec<Rect<f32>> = vec![];
        let mut filtered_sets: Vec<_> = sets
            .into_iter()
            .filter_map(|(mut set, anchor, offset)| {
                if anchor.w <= 0.0 {
                    // The point is in imaginary plane
                    return None;
                }

                let dx = anchor.x * size.width() / 2.0;
                let dy = anchor.y * size.height() / 2.0;

                let set_bbox = set.bbox.shift(dx as f32, dy as f32);

                if set.hide_on_overlay && displayed.iter().any(|bbox| bbox.intersects(set_bbox)) {
                    // Hiding the set
                    match set.state {
                        RenderSetState::Hidden => None,
                        RenderSetState::FadingIn { start_time } => {
                            let fade_out_start_time =
                                now + (now - start_time) - set.animation_duration;
                            set.state = RenderSetState::FadingOut {
                                start_time: fade_out_start_time,
                            };

                            Some((set, offset))
                        }
                        RenderSetState::Displayed => {
                            set.state = RenderSetState::FadingOut {
                                start_time: web_time::Instant::now(),
                            };
                            Some((set, offset))
                        }
                        RenderSetState::FadingOut { .. } => Some((set, offset)),
                    }
                } else {
                    // Showing the set
                    displayed.push(set_bbox);

                    match set.state {
                        RenderSetState::Hidden => {
                            set.state = RenderSetState::FadingIn {
                                start_time: web_time::Instant::now(),
                            };
                        }
                        RenderSetState::FadingOut { start_time } => {
                            let fade_in_start_time =
                                now + (now - start_time) - set.animation_duration;
                            set.state = RenderSetState::FadingIn {
                                start_time: fade_in_start_time,
                            };
                        }
                        _ => {}
                    }

                    Some((set, offset))
                }
            })
            .collect();

        let mut is_animating = false;
        let encoder = &mut *self.encoder;

        {
            let view = &self.renderer_targets.multisampling_view;
            let resolve_target = Some(self.view);
            let depth_view = &self.renderer_targets.stencil_view_multisample;

            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view,
                    depth_slice: None,
                    resolve_target,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Load,
                        store: StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: Some(RenderPassDepthStencilAttachment {
                    view: depth_view,
                    depth_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(1.0),
                        store: StoreOp::Discard,
                    }),
                    stencil_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(0),
                        store: StoreOp::Discard,
                    }),
                }),
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });

            let instances: Vec<DisplayInstance> = filtered_sets
                .iter_mut()
                .map(|(set, offset)| {
                    let opacity = match set.state {
                        RenderSetState::Hidden => 0.0,
                        RenderSetState::FadingIn { start_time } => {
                            is_animating = true;

                            let mut opacity = if set.animation_duration.is_zero() {
                                1.0
                            } else {
                                (now - start_time).as_millis() as f32
                                    / set.animation_duration.as_millis() as f32
                            };

                            if opacity >= 1.0 {
                                set.state = RenderSetState::Displayed;
                                opacity = 1.0;
                            }

                            opacity
                        }
                        RenderSetState::Displayed => 1.0,
                        RenderSetState::FadingOut { start_time } => {
                            is_animating = true;

                            let mut opacity = if set.animation_duration.is_zero() {
                                0.0
                            } else {
                                1.0 - ((now - start_time).as_millis() as f32
                                    / set.animation_duration.as_millis() as f32)
                            };

                            if opacity <= 0.0 {
                                set.state = RenderSetState::Hidden;
                                opacity = 0.0;
                            }

                            opacity
                        }
                    };

                    let anchor = [
                        set.anchor_point[0] + offset.dx(),
                        set.anchor_point[1] + offset.dy(),
                        set.anchor_point[2],
                    ];

                    DisplayInstance {
                        opacity,
                        offset: anchor,
                    }
                })
                .collect();

            let display_buffer =
                self.renderer
                    .device
                    .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: None,
                        usage: wgpu::BufferUsages::VERTEX,
                        contents: bytemuck::cast_slice(&instances),
                    });

            render_pass.set_vertex_buffer(1, display_buffer.slice(..));

            for (index, set) in filtered_sets.iter().enumerate().rev() {
                self.renderer_targets.pipelines.render_screen_set(
                    &set.0.data,
                    &mut render_pass,
                    index as u32,
                );
            }
        }

        is_animating
    }
}

struct WgpuPackedBundle {
    clip_area_buffers: Option<WgpuVertexBuffers>,
    map_ref_buffers: WgpuVertexBuffers,
    dot_buffers: Option<WgpuDotBuffers>,
    image_buffers: Vec<WgpuImage>,

    screen_sets: Vec<Arc<Mutex<WgpuScreenSet>>>,
}

struct WgpuScreenSet {
    state: RenderSetState,
    animation_duration: Duration,
    anchor_point: [f32; 3],
    bbox: Rect<f32>,
    hide_on_overlay: bool,
    data: WgpuScreenSetData,
}

enum WgpuScreenSetData {
    Vertex(WgpuVertexBuffers),
    Image(WgpuImage),
}

struct WgpuVertexBuffers {
    vertex: Buffer,
    index: Buffer,
    index_count: u32,
}

struct WgpuDotBuffers {
    buffer: Buffer,
    point_count: u32,
}

impl WgpuPackedBundle {
    fn new(
        bundle: &RenderBundle,
        renderer: &WgpuRenderer,
        renderer_targets: &RendererTargets,
        pending: &Mutex<Vec<ImageUpload>>,
    ) -> Self {
        let RenderBundle {
            world_set,
            screen_sets: bundle_screen_sets,
        } = bundle;
        let WorldRenderSet {
            poly_tessellation,
            points,
            images,
            clip_area,
            image_store,
            ..
        } = world_set;

        let clip_area_buffers = clip_area
            .as_ref()
            .map(|v| Self::write_poly_buffers(v, renderer));

        let poly_buffers = Self::write_poly_buffers(poly_tessellation, renderer);

        let dot_buffers = if points.is_empty() {
            None
        } else {
            let point_instance_buffer =
                renderer
                    .device
                    .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: None,
                        usage: wgpu::BufferUsages::VERTEX,
                        contents: bytemuck::cast_slice(points),
                    });
            let count = points.len();
            Some(WgpuDotBuffers {
                buffer: point_instance_buffer,
                point_count: count as u32,
            })
        };

        let textures: Vec<_> = image_store
            .iter()
            .map(|decoded_image| renderer.get_or_create_image_texture(decoded_image, pending))
            .collect();

        let mut image_buffers = vec![];
        for image_info in images {
            let image = renderer_targets.pipelines.image_pipeline().create_image(
                &renderer.device,
                textures
                    .get(image_info.store_index)
                    .expect("texture at index must exist")
                    .clone(),
                &image_info.vertices,
            );
            image_buffers.push(image);
        }

        let mut screen_sets = vec![];
        for bundle_screen_set in bundle_screen_sets {
            let data = match &bundle_screen_set.data {
                ScreenSetData::Vertices(buffers) => {
                    let index_buffer =
                        renderer
                            .device
                            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                                label: None,
                                contents: bytemuck::cast_slice(&buffers.indices),
                                usage: wgpu::BufferUsages::INDEX,
                            });

                    let vertex_buffer =
                        renderer
                            .device
                            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                                label: None,
                                usage: wgpu::BufferUsages::VERTEX,
                                contents: bytemuck::cast_slice(&buffers.vertices),
                            });

                    let buffers = WgpuVertexBuffers {
                        index: index_buffer,
                        vertex: vertex_buffer,
                        index_count: buffers.indices.len() as u32,
                    };

                    WgpuScreenSetData::Vertex(buffers)
                }
                ScreenSetData::Image { vertices, bitmap } => {
                    let bind_group = renderer.get_or_create_image_texture(bitmap, pending);
                    let image = renderer_targets
                        .pipelines
                        .screen_set_image_pipeline()
                        .create_image(&renderer.device, bind_group, vertices);
                    WgpuScreenSetData::Image(image)
                }
            };

            screen_sets.push(Arc::new(Mutex::new(WgpuScreenSet {
                state: RenderSetState::Hidden,
                animation_duration: bundle_screen_set.animation_duration,
                anchor_point: bundle_screen_set.anchor_point,
                bbox: bundle_screen_set.bbox,
                hide_on_overlay: bundle_screen_set.hide_on_overlay,
                data,
            })));
        }

        Self {
            clip_area_buffers,
            map_ref_buffers: poly_buffers,
            image_buffers,
            dot_buffers,
            screen_sets,
        }
    }

    fn write_poly_buffers(
        tessellation: &VertexBuffers<PolyVertex, u32>,
        renderer: &WgpuRenderer,
    ) -> WgpuVertexBuffers {
        let index_bytes = bytemuck::cast_slice(&tessellation.indices);
        let bytes = bytemuck::cast_slice(&tessellation.vertices);

        let index = renderer
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                contents: index_bytes,
                usage: wgpu::BufferUsages::INDEX,
            });

        let vertex = renderer
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                contents: bytes,
            });

        WgpuVertexBuffers {
            index,
            vertex,
            index_count: tessellation.indices.len() as u32,
        }
    }
}

impl PackedBundle for WgpuPackedBundle {
    fn as_any(&self) -> &dyn Any {
        self
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct ViewUniform {
    view_proj: [[f32; 4]; 4],
    view_rotation: [[f32; 4]; 4],
    inv_screen_size: [f32; 2],
    resolution: f32,
    _padding: [f32; 1],
}

impl PointInstance {
    fn wgpu_desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: size_of::<PointInstance>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Instance,
            attributes: &[
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 0,
                    format: wgpu::VertexFormat::Float32x3,
                },
                wgpu::VertexAttribute {
                    offset: (size_of::<[f32; 3]>()) as wgpu::BufferAddress,
                    shader_location: 1,
                    format: wgpu::VertexFormat::Uint8x4,
                },
            ],
        }
    }
}

impl PolyVertex {
    fn wgpu_desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: size_of::<PolyVertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &[
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 0,
                    format: wgpu::VertexFormat::Float32x3,
                },
                wgpu::VertexAttribute {
                    offset: size_of::<[f32; 3]>() as wgpu::BufferAddress,
                    shader_location: 1,
                    format: wgpu::VertexFormat::Float32x4,
                },
                wgpu::VertexAttribute {
                    offset: (size_of::<[f32; 3]>() + size_of::<[f32; 4]>()) as wgpu::BufferAddress,
                    shader_location: 2,
                    format: wgpu::VertexFormat::Float32x2,
                },
                wgpu::VertexAttribute {
                    offset: (size_of::<[f32; 3]>() + size_of::<[f32; 4]>() + size_of::<[f32; 2]>())
                        as wgpu::BufferAddress,
                    shader_location: 3,
                    format: wgpu::VertexFormat::Float32,
                },
            ],
        }
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct DisplayInstance {
    pub opacity: f32,
    pub offset: [f32; 3],
}

impl DisplayInstance {
    fn wgpu_desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: size_of::<DisplayInstance>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Instance,
            attributes: &[
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 10,
                    format: wgpu::VertexFormat::Float32,
                },
                wgpu::VertexAttribute {
                    offset: size_of::<f32>() as wgpu::BufferAddress,
                    shader_location: 11,
                    format: wgpu::VertexFormat::Float32x3,
                },
            ],
        }
    }
}
