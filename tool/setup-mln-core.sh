#!/usr/bin/env bash
set -euo pipefail

# Caches a prebuilt, non-amalgamated MapLibre Native core (plus its vendor
# libraries and the headers the cxx bridge needs) so every subsequent build
# links against them instead of recompiling the C++ engine from source.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.cache/mln-core"
MLN_RELEASE="core-a33d3f00fb9dbf9117ce18edd799aa0ca5bcce5b"
CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"

mkdir -p "$CACHE" "$CACHE/vendor/maplibre-tile-spec/cpp" "$CACHE/webgpu-cpp" "$CACHE/src"

if [ ! -f "$CACHE/maplibre-native-headers.tar.gz" ]; then
  echo "Downloading MapLibre Native public headers..." >&2
  curl -fL --retry 3 -o "$CACHE/maplibre-native-headers.tar.gz" \
    "https://github.com/maplibre/maplibre-native/releases/download/${MLN_RELEASE}/maplibre-native-headers.tar.gz"
fi

# Build the core once if it is missing.
if [ ! -f "$CACHE/libmbgl-core.a" ]; then
  echo "Building the MapLibre Native core once (the slow step)..." >&2

  # Build from outside the repository so this repo's .cargo/config.toml does
  # not force precompiled mode; the source build is what produces the archives.
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  (
    cd "$scratch"
    MLN_CORE_LIBRARY_USE_AMALGAM=0 cargo build --manifest-path "$ROOT/rust/Cargo.toml"
  )

  core="$(find "$ROOT/rust/target" -type f -name 'libmbgl-core.a' | head -1)"
  if [ -z "$core" ]; then
    echo "error: the source build did not produce libmbgl-core.a" >&2
    exit 1
  fi
  build_dir="$(dirname "$core")"

  for lib in mbgl-core mbgl-freetype mbgl-harfbuzz mbgl-vendor-csscolorparser mbgl-vendor-nunicode mbgl-vendor-parsedate mbgl-vendor-sqlite; do
    cp "$build_dir/lib$lib.a" "$CACHE/"
  done
  cp "$build_dir/vendor/maplibre-tile-spec/cpp/libmlt-cpp.a" \
     "$build_dir/vendor/maplibre-tile-spec/cpp/libfastpfor-lib.a" \
     "$CACHE/vendor/maplibre-tile-spec/cpp/"
fi

# Locate an existing build directory (the one-time build may already have run).
if [ -z "${build_dir:-}" ]; then
  core="$(find "$ROOT/rust/target" "$ROOT/example/runner-rs/target" -type f -name 'libmbgl-core.a' 2>/dev/null | head -1)"
  if [ -n "$core" ]; then
    build_dir="$(dirname "$core")"
  fi
fi

# Refresh the cmake-generated WebGPU C++ headers when missing.
if [ -n "${build_dir:-}" ] && [ -d "$build_dir/webgpu-cpp" ] && [ ! -f "$CACHE/webgpu-cpp/webgpu.hpp" ]; then
  cp -r "$build_dir/webgpu-cpp/." "$CACHE/webgpu-cpp/"
fi

# The public header archive omits internal src/ headers, so cache them from the
# maplibre-native checkout that cargo cloned during the source build.
if [ ! -f "$CACHE/src/mln/gfx/offscreen_texture.hpp" ]; then
  mln_src="$(find "$CARGO_HOME_DIR/git/checkouts" -type d -path '*/maplibre-native-rs-*/*/target/maplibre-native/src' 2>/dev/null | head -1)"
  if [ -n "$mln_src" ]; then
    cp -r "$mln_src/." "$CACHE/src/"
  else
    echo "warning: could not locate the maplibre-native checkout to cache internal headers" >&2
  fi
fi

echo "MapLibre Native core cache is ready: $CACHE" >&2
