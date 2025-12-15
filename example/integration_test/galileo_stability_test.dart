import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/multi_session_test.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Galileo: create, zoom, and dispose multiple sessions safely',
    (tester) async {
      // Init FFI (this ONLY works in integration_test)
      await initGalileo();

      final size = MapSize(width: 300, height: 200);
      final config = MapInitConfig(
        backgroundColor: (0.1, 0.1, 0.1, 1),
        enableMultisampling: true,
        latlon: (0.0, 0.0),
        mapSize: size,
        zoomLevel: 5,
      );

      // Create many sessions (stress)
      final controllers =
          await MultiSessionTest.createSessions(10, size, config);

      expect(controllers.length, 10);

      // Zoom each session
      for (final controller in controllers) {
        final cx = controller.size.width / 2;
        final cy = controller.size.height / 2;

        controller.handleEvent(
          UserEvent.zoom(0.9, Point2(x: cx, y: cy)),
        );
      }

      // Dispose asynchronously (Tokio/WrongThread test)
      for (final controller in List.of(controllers)) {
        await controller.dispose();
      }

      // If we reach here without panic → PASS
      expect(true, isTrue);
    },
  );
}
