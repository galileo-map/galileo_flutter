# Galileo Flutter - Agent Guide

## Project Overview
Galileo Flutter is a Flutter FFI plugin that integrates the Galileo mapping engine with Flutter applications. It allows Flutter apps to leverage the powerful Galileo mapping library through Rust FFI bindings.

## Architecture
- **Flutter Layer** (`./lib`): Flutter/Dart abstractions and API
- **Interop Layer** (`./rust/api`): FFI functions and type definitions
- **Core Logic** (`./rust/src`): Core Rust implementation using the Galileo library

## Key Dependencies
- galileo: Core mapping library (v0.2.1), vendored under `./rust/vendor/galileo` with a patched wgpu renderer
- flutter_rust_bridge: FFI bridge generator
- flutter-plugin-sdk: Rust-shell plugin API; its `gpu::wgpu` re-export is the only wgpu source this project compiles against

## Build Process
1. Ensure Rust and Flutter are installed
2. Install `flutter_rust_bridge_codegen` if modifying Rust-Dart interop
3. Run `flutter_rust_bridge_codegen generate` after Rust API changes
4. Build with standard Flutter commands

## Development Commands
- `cd example && flutter run`: Run the example app
- `cargo check`: Check Rust compilation
- `flutter pub get`: Get Flutter dependencies
- `dart format .`: Format Dart code
- `cargo fmt`: Format Rust code

## Known Issues & Notes
- Galileo is vendored (not a git dependency) because its `WgpuRenderer` was adapted to record into the Rust shell's command encoders. The vendored renderer uses `flutter_plugin_sdk::gpu::wgpu` so it shares the shell's wgpu 30 revision.
- Maps are presented through shell-owned `WgpuTexture` rings (`GpuTextures::create_texture`). Galileo renders directly into those texture views; the old CPU pixel-buffer path was removed.
- TileSchema::test_schema() was replaced with TileSchema::web(19) due to API changes in the upstream Galileo library
- The example app requires desktop variant when running (not web)

## Common Tasks
1. Adding new API functions: Define in `./rust/api` and regenerate with `flutter_rust_bridge_codegen`
2. Modifying rendering: Look at `./rust/src/core/windowless_renderer.rs`, `./rust/src/core/flutter/wgpu_texture.rs`, and the vendored `rust/vendor/galileo/galileo/src/render/wgpu/mod.rs`
3. Working with maps: Check `./rust/src/core/galileo_ref.rs` and `./rust/src/core/map_session.rs`

## Project Structure
```
galileo_flutter/
├── lib/                    # Flutter/Dart code
├── rust/
│   ├── src/
│   │   ├── api/           # API definitions for FFI
│   │   ├── core/          # Core implementation
│   │   └── ...            # Other Rust modules
│   ├── vendor/galileo/    # Vendored, patched Galileo workspace
│   └── Cargo.toml         # Rust dependencies
├── example/               # Example Flutter app
├── test_driver/           # Integration tests
└── ...
```

## Configuration Files
- `flutter_rust_bridge.yaml`: FFI bridge configuration
- `pubspec.yaml`: Flutter dependencies
- `rust/Cargo.toml`: Rust dependencies
