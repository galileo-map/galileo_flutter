import 'dart:math';
import 'package:galileo_flutter/galileo_flutter.dart';

class MultiSessionTest {
  /// Create N map sessions with given size and config
  static Future<List<GalileoMapController>> createSessions(
      int count, MapSize size, MapInitConfig config) async {
    List<GalileoMapController> controllers = [];

    for (int i = 0; i < count; i++) {
      final result = await GalileoMapController.create(
        size: size,
        config: config,
      );

      final controller = result.$1; // controller
      final error = result.$2; // error message if any

      if (controller != null) {
        controllers.add(controller);
        print('Created map session #$i');
      } else {
        print('Failed to create session #$i - error: $error');
      }
    }

    return controllers;
  }

  /// Randomly dispose one session from the list
  static void disposeRandomly(List<GalileoMapController> controllers) {
    if (controllers.isEmpty) return;
    final index = Random().nextInt(controllers.length);

    controllers[index].dispose();
    print('Disposed map session #$index');
    controllers.removeAt(index);
  }
}
