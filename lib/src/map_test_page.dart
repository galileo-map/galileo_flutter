import 'dart:math';

import 'package:flutter/material.dart';
import 'package:galileo_flutter/src/galileo_map_controller.dart';
import 'package:galileo_flutter/src/rust/api/api.dart' as api;
import 'package:irondash_engine_context/irondash_engine_context.dart';

class MapTestPage extends StatefulWidget {
  const MapTestPage({super.key});

  @override
  State<MapTestPage> createState() => _MapTestPageState();
}

class _MapTestPageState extends State<MapTestPage> {
  final List<GalileoMapController> _controllers = [];
  final List<int> _sessionIds = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _createSessions(3); // Create 3 map sessions
  }

  Future<void> _createSessions(int count) async {
    setState(() => _loading = true);

    final engineHandle = await EngineContext.instance.getEngineHandle();

    for (int i = 0; i < count; i++) {
      final config = MapInitConfig(
        initialZoom: 3.0,
        centerLat: 0,
        centerLng: 0,
      );

      final response = await api.createNewMapSession(
        engineHandle: engineHandle,
        config: config,
      );

      final controller = GalileoMapController._(
        size: MapSize(width: 400, height: 300),
        config: config,
        layers: [LayerConfig.osm()],
        sessionId: response.sessionId,
        stateBroadcast: rx.BehaviorSubject.seeded(GalileoMapState.initializing),
        originalSub: null,
      );

      controller._textureId = response.textureId;
      controller._running = true;

      _controllers.add(controller);
      _sessionIds.add(response.sessionId);

      debugPrint(
          "Session ${response.sessionId} created with texture ${response.textureId}");
    }

    setState(() => _loading = false);
  }

  Future<void> _disposeRandomSession() async {
    if (_controllers.isEmpty) return;

    final index = Random().nextInt(_controllers.length);
    final controller = _controllers.removeAt(index);

    await controller.dispose();
    _sessionIds.remove(controller.sessionId);

    debugPrint("Disposed session ${controller.sessionId}");
    setState(() {});
  }

  Future<void> _redrawAllMaps() async {
    for (final controller in _controllers) {
      await controller.requestRedraw();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Map Session Test"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ElevatedButton(
                  onPressed: _disposeRandomSession,
                  child: const Text("Dispose Random Session"),
                ),
                ElevatedButton(
                  onPressed: _redrawAllMaps,
                  child: const Text("Redraw All Maps"),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _controllers.length,
                    itemBuilder: (context, index) {
                      final controller = _controllers[index];
                      return Card(
                        margin: const EdgeInsets.all(8),
                        child: SizedBox(
                          width: 400,
                          height: 300,
                          child: Center(
                            child: Text(
                              "Map Session ${controller.sessionId}",
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
