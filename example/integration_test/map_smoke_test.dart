import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a simple map without error', (tester) async {
    await initGalileo();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalileoMapWidget.fromConfig(
            size: const MapSize(width: 400, height: 300),
            config: MapInitConfig(
              latlon: const GeoLocation(latitude: 0.0, longitude: 0.0),
              zoomLevel: 2,
              mapSize: const MapSize(width: 400, height: 300),
              enableMultisampling: false,
              backgroundColor: const Color(0xFF1A1A1A).toGalileo(),
            ),
            // No layers: this is a render smoke test, not a tile-loading test,
            // so it must not depend on network access in CI.
            layers: const [],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(GalileoMapWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
