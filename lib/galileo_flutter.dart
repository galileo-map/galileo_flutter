library;

import 'dart:ffi' as ffi;

import 'package:path_provider/path_provider.dart';

export 'package:galileo_flutter/src/map/widget.dart' show GalileoMapWidget;

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
        Point2,
        MapPosition,
        Point,
        PointStyle;
export 'package:galileo_flutter/src/map/widget.dart';
export 'package:galileo_flutter/src/map/controller.dart';
export 'package:galileo_flutter/src/layer/overlay.dart';
export 'package:galileo_flutter/src/overlay/overlay_widget.dart';
export 'package:galileo_flutter/src/overlay/polygon_draw_controller.dart';
export 'package:galileo_flutter/src/overlay/overlay_polygon.dart';
export 'package:galileo_flutter/src/layer/controller.dart';
export 'package:galileo_flutter/src/feature/edit_controller.dart';

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
