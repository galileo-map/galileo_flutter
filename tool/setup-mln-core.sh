#!/usr/bin/env bash
set -euo pipefail

# Caches a prebuilt, non-amalgamated MapLibre Native core (plus its vendor
# libraries) so every subsequent build links against them instead of
# recompiling the C++ engine from source.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.cache/mln-core"
MLN_RELEASE="core-a33d3f00fb9dbf9117ce18edd799aa0ca5bcce5b"

mkdir -p "$CACHE"

if [ ! -f "$CACHE/maplibre-native-headers.tar.gz" ]; then
  echo "Downloading MapLibre Native public headers..." >&2
  curl -fL --retry 3 -o "$CACHE/maplibre-native-headers.tar.gz" \
    "https://github.com/maplibre/maplibre-native/releases/download/${MLN_RELEASE}/maplibre-native-headers.tar.gz"
fi

if [ -f "$CACHE/libmbgl-core.a" ]; then
  echo "MapLibre Native core cache is ready: $CACHE" >&2
  exit 0
fi

echo "Building the MapLibre Native core once (the slow step)..." >&2

# Build from outside the repository so this repo's .cargo/config.toml does not
# force precompiled mode; the source build is what produces the core archives.
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
mkdir -p "$CACHE/vendor/maplibre-tile-spec/cpp"
for lib in mbgl-core mbgl-freetype mbgl-harfbuzz mbgl-vendor-csscolorparser mbgl-vendor-nunicode mbgl-vendor-parsedate mbgl-vendor-sqlite; do
  cp "$build_dir/lib$lib.a" "$CACHE/"
done
cp "$build_dir/vendor/maplibre-tile-spec/cpp/libmlt-cpp.a" \
   "$build_dir/vendor/maplibre-tile-spec/cpp/libfastpfor-lib.a" \
   "$CACHE/vendor/maplibre-tile-spec/cpp/"
if [ -d "$build_dir/webgpu-cpp" ]; then
  mkdir -p "$CACHE/webgpu-cpp"
  cp -r "$build_dir/webgpu-cpp/." "$CACHE/webgpu-cpp/"
fi
mln_src="$ROOT/rust/vendor/maplibre-native-rs/target/maplibre-native/src"
if [ -d "$mln_src" ]; then
  mkdir -p "$CACHE/src"
  cp -r "$mln_src/." "$CACHE/src/"
fi
echo "Cached the MapLibre Native core at $CACHE" >&2
