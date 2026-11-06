library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
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

/// Whether the plugin's Rust code is linked into the running process, as it is
/// under the Rust shell, instead of living in a separate `libgalileo_flutter`.
///
/// Older runners announced this with `FLUTTER_RUST_SHELL=1`; newer ones do not,
/// so also look for flutter_rust_bridge's exported symbols in the process.
bool _isRustShell() {
  if (Platform.environment['FLUTTER_RUST_SHELL'] == '1') {
    return true;
  }
  try {
    return ffi.DynamicLibrary.process().providesSymbol(
      'frb_get_rust_content_hash',
    );
  } catch (_) {
    return false;
  }
}

Future<void> initGalileo({String? cachePath}) async {
  final isRustShell = _isRustShell();
  await rlib_gen.RustLib.init(
    externalLibrary: isRustShell
        ? ExternalLibrary.process(iKnowHowToUseIt: true)
        : null,
  );
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
