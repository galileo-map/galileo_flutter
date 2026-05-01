library;

import 'dart:ffi' as ffi;

import 'package:path_provider/path_provider.dart';

export 'package:galileo_flutter/src/galileo_map_widget.dart'
    show GalileoMapWidget;

import 'src/rust/api/galileo_api.dart' as rlib;
import 'src/rust/frb_generated.dart' as rlib_gen;

export 'package:galileo_flutter/src/rust/api/dart_types.dart'
    show
        MapViewport,
        MapSize,
        LayerConfig,
        MapInitConfig,
        Polygon,
        PolygonStyle,
        Color,
        Point,
        PointStyle;

Future<void> initGalileo({String? cachePath}) async {
  await rlib_gen.RustLib.init();
  rlib.galileoFlutterInit(ffiPtr: ffi.NativeApi.initializeApiDLData.address);

  String? tileCachePath = cachePath;
  if (tileCachePath == null) {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      tileCachePath = '${cacheDir.path}/tile_cache';
    } catch (e) {
      tileCachePath = null;
    }
  }

  await rlib.setTileCachePath(path: tileCachePath);
}
