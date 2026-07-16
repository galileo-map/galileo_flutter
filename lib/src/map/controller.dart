import 'dart:async';

import 'package:galileo_flutter/src/rust/api/dart_types.dart';
import 'package:galileo_flutter/src/rust/api/galileo_api.dart' as rlib;
import 'package:galileo_flutter/src/layer/controller.dart';
import 'package:logging/logging.dart';

import 'package:irondash_engine_context/irondash_engine_context.dart';
import "package:rxdart/rxdart.dart" as rx;

final _log = Logger('GalileoMapController');

/// State of a Galileo map instance
enum GalileoMapState {
  /// Map is being initialized
  initializing,

  /// Map is ready and rendering
  ready,

  /// Map encountered an error
  error,

  /// Map has been stopped/destroyed
  stopped,
}

/// Controller for managing a Galileo map instance
class GalileoMapController {
  MapSize _size;
  MapSize get size => _size;
  final MapInitConfig config;

  late final LayerController layerController;

  final List<LayerConfig> layers;

  final int sessionId;
  final rx.BehaviorSubject<GalileoMapState> _stateBroadcast;
  final rx.BehaviorSubject<MapViewport> _renderedViewportBroadcast =
      rx.BehaviorSubject<MapViewport>();
  StreamSubscription<RenderedMapFrame>? _renderedFrameSub;
  BigInt _lastRenderedFrameSequence = BigInt.zero;
  Future<void> _eventQueue = Future<void>.value();
  bool _running = false;
  int? _textureId;

  GalileoMapController._({
    required MapSize size,
    required this.config,
    required this.layers,
    required this.sessionId,
    required rx.BehaviorSubject<GalileoMapState> stateBroadcast,
  }) : _size = size,
       _stateBroadcast = stateBroadcast {
    layerController = LayerController(sessionId: sessionId, layers: layers);
  }

  /// Stream of map state changes
  Stream<GalileoMapState> get stateStream => _stateBroadcast.stream;

  /// Current map state
  GalileoMapState get currentState => _stateBroadcast.value;

  /// Viewports that produced completed native texture frames.
  Stream<MapViewport> get renderedViewportStream =>
      _renderedViewportBroadcast.stream;

  /// Texture ID for rendering (null if not ready)
  int? get textureId => _textureId;

  /// Whether the map is currently running
  bool get isRunning => _running;

  /// Create a new Galileo map controller
  static Future<(GalileoMapController?, String?)> create({
    required MapSize size,
    required MapInitConfig config,
    List<LayerConfig> layers = const [LayerConfig.osm()],
  }) async {
    try {
      // Get Flutter engine handle for texture registration
      final handle = await EngineContext.instance.getEngineHandle();

      // Create the map instance
      final newSessionResp = await rlib.createNewMapSession(
        engineHandle: handle,
        config: config,
      );

      // Create state broadcast
      final stateBroadcast = rx.BehaviorSubject<GalileoMapState>.seeded(
        GalileoMapState.initializing,
      );

      final controller = GalileoMapController._(
        size: size,
        config: config,
        layers: layers,
        sessionId: newSessionResp.sessionId,
        stateBroadcast: stateBroadcast,
      );

      for (final layer in layers) {
        await controller.layerController.addLayer(layer);
      }

      controller._textureId = newSessionResp.textureId;
      controller._running = true;
      controller._startRenderedFrameStream();

      await rlib.requestMapRedraw(sessionId: controller.sessionId);

      // Start session keep-alive task
      controller._startKeepAliveTask();

      // Set state to ready
      controller._stateBroadcast.add(GalileoMapState.ready);

      return (controller, null);
    } catch (e) {
      _log.severe('Error creating Galileo map', e);
      return (null, e.toString());
    }
  }

  void _startRenderedFrameStream() {
    _renderedFrameSub = rlib
        .streamRenderedMapFrames(sessionId: sessionId)
        .listen(
          (frame) {
            if (!_running || frame.sequence <= _lastRenderedFrameSequence) {
              return;
            }
            _lastRenderedFrameSequence = frame.sequence;
            layerController.updateViewport(frame.viewport, frame.mapSize);
            _renderedViewportBroadcast.add(frame.viewport);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_running) {
              _log.warning('Rendered-frame stream failed', error, stackTrace);
            }
          },
        );
  }

  /// Start the session keep-alive task
  void _startKeepAliveTask() {
    Future.microtask(() async {
      while (_running) {
        try {
          // Ping Rust side to announce we still want the stream
          await rlib.markSessionAlive(sessionId: sessionId);
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          _log.severe('Error in keep-alive task', e);
          if (_running) {
            _stateBroadcast.add(GalileoMapState.error);
          }
          break;
        }
      }
    });
  }

  /// Handle user events from the map widget
  Future<void> handleEvent(UserEvent event) {
    if (!_running) return Future<void>.value();

    _eventQueue = _eventQueue.then((_) async {
      try {
        await rlib.handleEventForSession(sessionId: sessionId, event: event);
      } catch (e) {
        _log.warning('Error handling event', e);
      }
    });
    return _eventQueue;
  }

  Future<void> requestRedraw() async {
    await rlib.requestMapRedraw(sessionId: sessionId);
  }

  /// Get the current map viewport
  Future<MapViewport?> getViewport() async {
    return rlib.getMapViewport(sessionId: sessionId);
  }

  /// Set the map viewport
  Future<void> setViewport(MapViewport viewport) async {
    if (!_running) return;
  }

  /// Resize the map
  Future<void> resize(MapSize newSize) async {
    if (!_running) return;
    try {
      await rlib.resizeSession(sessionId: sessionId, newSize: newSize);
      _size = newSize;
    } catch (e) {
      _log.severe('Error resizing map', e);
    }
  }

  /// Dispose of the controller and clean up resources
  Future<void> dispose() async {
    _running = false;

    try {
      await rlib.destroySession(sessionId: sessionId);
      await _renderedFrameSub?.cancel();
      await _renderedViewportBroadcast.close();
      await _stateBroadcast.close();
    } catch (e) {
      _log.severe('Error disposing Galileo map controller', e);
    }
  }
}
