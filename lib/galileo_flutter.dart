library galileo_flutter;

import 'dart:ffi' as ffi;

//
// ⭐ EXPORT ALL PUBLIC API FILES
//
export 'src/galileo_map_widget.dart';
export 'src/galileo_map_controller.dart';
export 'src/multi_session_test.dart';

// Rust bridge exports
export 'src/rust/api/dart_types.dart'
    show MapViewport, MapSize, LayerConfig, MapInitConfig;

import 'src/rust/api/api.dart' as rlib;
import 'src/rust/frb_generated.dart' as rlib_gen;

//
// ⭐ INITIALIZER
//
Future<void> initGalileo() async {
  await rlib_gen.RustLib.init();
  rlib.galileoFlutterInit(
    ffiPtr: ffi.NativeApi.initializeApiDLData.address,
  );
}
