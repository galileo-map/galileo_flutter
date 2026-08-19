library;

import 'dart:ffi' as ffi;

import 'package:path_provider/path_provider.dart';

export 'package:galileo_flutter/src/map/widget.dart' show GalileoMapWidget;

import 'src/rust/api/galileo_api.dart' as rlib;
import 'src/rust/frb_generated.dart' as rlib_gen;

export 'package:galileo_flutter/src/rust/api/dart_types.dart'
    show
        GeoLocation,
        ScreenLocation,
        MapViewport,
        MapSize,
        LayerConfig,
        MapInitConfig,
        Polygon,
        PolygonStyle,
        GalileoColor,
        Point2,
        Point,
		  UserEvent,
        PointStyle;
export 'package:galileo_flutter/src/map/widget.dart';
export 'package:galileo_flutter/src/extensions/color.dart';
export 'package:galileo_flutter/src/map/controller.dart';
export 'package:galileo_flutter/src/layer/overlay/overlay.dart';
export 'package:galileo_flutter/src/layer/feature/feature.dart';
export 'package:galileo_flutter/src/overlay/widget/overlay_widget.dart';
export 'package:galileo_flutter/src/overlay/polygon/polygon_draw_controller.dart';
export 'package:galileo_flutter/src/overlay/polygon/polygon_edit_controller.dart';
export 'package:galileo_flutter/src/overlay/polygon/overlay_polygon.dart';
export 'package:galileo_flutter/src/layer/controller.dart';
export 'package:galileo_flutter/src/widgets/polygon_overlay.dart';
export 'package:galileo_flutter/src/widgets/cluster/cluster_controller.dart';
export 'package:galileo_flutter/src/widgets/cluster/cluster_overlay.dart';

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
