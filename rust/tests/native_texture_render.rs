//! Headless smoke test for the native GPU texture render path.
//!
//! Creates a real wgpu device, renders an empty Galileo map through
//! `WindowlessRenderer` into an externally owned texture, and verifies the
//! background clear reaches the texture. The test skips itself when no
//! Vulkan adapter is available.

use flutter_plugin_sdk::gpu::wgpu;
use futures::executor::block_on;
use galileo::galileo_types::cartesian::Size;
use galileo::layer::FeatureLayer;
use galileo::symbol::ImagePointSymbol;
use galileo::MapBuilder;
use galileo_flutter::core::WindowlessRenderer;

const SIZE: u32 = 128;

/// A 16x16 solid red RGBA PNG used as the image marker.
const RED_PNG: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0xF3, 0xFF,
    0x61, 0x00, 0x00, 0x00, 0x19, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
    0x9F, 0x12, 0xCC, 0x30, 0x6A, 0xC0, 0xA8, 0x01, 0xA3, 0x06, 0x0C, 0x17, 0x03, 0x00, 0x30, 0xC4,
    0xFE, 0x10, 0x1C, 0x27, 0xE4, 0x00, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
    0x60, 0x82,
];

#[test]
fn renders_into_external_texture_without_pixel_buffer() {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        flags: Default::default(),
        memory_budget_thresholds: Default::default(),
        backend_options: Default::default(),
        display: None,
    });

    let adapter = match block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::default(),
        force_fallback_adapter: false,
        compatible_surface: None,
        apply_limit_buckets: false,
    })) {
        Ok(adapter) => adapter,
        Err(_) => {
            eprintln!("skipping native texture render test: no wgpu adapter available");
            return;
        }
    };

    let (device, queue) = match block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: None,
        required_features: wgpu::Features::empty(),
        required_limits: wgpu::Limits::default(),
        memory_hints: wgpu::MemoryHints::default(),
        trace: wgpu::Trace::Off,
        experimental_features: wgpu::ExperimentalFeatures::disabled(),
    })) {
        Ok(device_queue) => device_queue,
        Err(_) => {
            eprintln!("skipping native texture render test: no wgpu device available");
            return;
        }
    };

    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("native texture render test target"),
        size: wgpu::Extent3d {
            width: SIZE,
            height: SIZE,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let target_view = target.create_view(&wgpu::TextureViewDescriptor::default());

    let mut map = MapBuilder::default().build();
    map.set_size(Size::new(SIZE as f64, SIZE as f64));

    let mut renderer = WindowlessRenderer::new(Size::new(SIZE, SIZE));
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    renderer.render(&map, &device, &mut encoder, &target_view);
    queue.submit(Some(encoder.finish()));

    // Read back one pixel to confirm the clear pass ran on the GPU.
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("native texture render test readback"),
        size: 256,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(256),
                rows_per_image: Some(1),
            },
        },
        wgpu::Extent3d {
            width: 1,
            height: 1,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));

    let slice = readback.slice(..);
    block_on(async {
        let (sender, receiver) = futures::channel::oneshot::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });
        let _ = device.poll(wgpu::PollType::Wait {
            submission_index: None,
            timeout: Some(std::time::Duration::from_secs(5)),
        });
        receiver
            .await
            .expect("readback mapping channel closed")
            .expect("readback mapping failed");
    });

    let data = slice
        .get_mapped_range()
        .expect("readback buffer should be mapped");
    assert_eq!(
        &data[..4],
        &[255, 255, 255, 255],
        "the default white background must be resolved into the target texture"
    );
    drop(data);

    // Render a feature layer that carries an image marker. This exercises the
    // staging-buffer image upload recorded into the externally supplied
    // encoder before the screen-set render pass.
    let symbol = ImagePointSymbol::from_bytes(
        RED_PNG,
        galileo::galileo_types::cartesian::Vector2::new(0.0, 0.0),
        1.0,
    )
    .expect("image symbol should decode");
    map.layers_mut().push(FeatureLayer::new(
        vec![galileo::galileo_types::latlon!(0.0, 0.0)],
        symbol,
        galileo::galileo_types::geo::Crs::WGS84,
    ));
    map.redraw();

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    renderer.render(&map, &device, &mut encoder, &target_view);
    queue.submit(Some(encoder.finish()));

    let full_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("native texture render test full readback"),
        size: (SIZE * SIZE * 4) as wgpu::BufferAddress,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &full_readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(SIZE * 4),
                rows_per_image: Some(SIZE),
            },
        },
        wgpu::Extent3d {
            width: SIZE,
            height: SIZE,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));

    let slice = full_readback.slice(..);
    block_on(async {
        let (sender, receiver) = futures::channel::oneshot::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });
        let _ = device.poll(wgpu::PollType::Wait {
            submission_index: None,
            timeout: Some(std::time::Duration::from_secs(5)),
        });
        receiver
            .await
            .expect("readback mapping channel closed")
            .expect("readback mapping failed");
    });
    let data = slice
        .get_mapped_range()
        .expect("readback buffer should be mapped");
    let has_red_marker = data
        .as_chunks::<4>()
        .0
        .iter()
        .any(|pixel| pixel[0] > 200 && pixel[1] < 80 && pixel[2] < 80);
    assert!(
        has_red_marker,
        "the image marker must be uploaded and drawn through the external encoder"
    );
}
