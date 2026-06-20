import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galileo_flutter/src/map/controller.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart';
import 'package:flutter/scheduler.dart';
import 'package:galileo_flutter/src/layer/overlay.dart';

/// A widget that displays a Galileo map with interactive controls
class GalileoMapWidget extends StatefulWidget {
  final GalileoMapController controller;

  final MapInitConfig config;

  final List<LayerConfig> layers;

  final Widget? child;

  /// Whether to dispose the controller when the widget disposes
  final bool autoDispose;

  /// Whether to enable keyboard input
  final bool enableKeyboard;

  /// Focus node for keyboard events
  final FocusNode? focusNode;

  /// Called when the map is tapped
  final void Function(double x, double y)? onTap;

  /// Fires at most once per 30 ms to avoid flooding the Rust FFI layer.
  final void Function(MapViewport viewport)? onViewportChanged;

  const GalileoMapWidget._({
    super.key,
    required this.controller,
    required this.config,
    required this.layers,
    this.child,
    this.autoDispose = true,
    this.enableKeyboard = true,
    this.focusNode,
    this.onTap,
    this.onViewportChanged,
  });

  /// Create a GalileoMapWidget from an existing controller
  factory GalileoMapWidget.fromController({
    Key? key,
    required GalileoMapController controller,
    required MapInitConfig config,
    List<LayerConfig> layers = const [LayerConfig.osm()],
    bool autoDispose = true,
    bool enableKeyboard = true,
    FocusNode? focusNode,
    Widget? child,
    void Function(double x, double y)? onTap,
    void Function(MapViewport viewport)? onViewportChanged,
  }) {
    return GalileoMapWidget._(
      key: key,
      controller: controller,
      autoDispose: autoDispose,
      enableKeyboard: enableKeyboard,
      focusNode: focusNode,
      onTap: onTap,
      onViewportChanged: onViewportChanged,
      config: config,
      layers: layers,
      child: child,
    );
  }

  /// Create a GalileoMapWidget with configuration
  static Widget fromConfig({
    Key? key,
    required MapSize size,
    required MapInitConfig config,
    List<LayerConfig> layers = const [LayerConfig.osm()],
    bool autoDispose = true,
    bool enableKeyboard = true,
    FocusNode? focusNode,
    Widget? child,
    void Function(double x, double y)? onTap,
    void Function(MapViewport viewport)? onViewportChanged,
  }) {
    return _GalileoMapFromConfig(
      key: key,
      size: size,
      config: config,
      layers: layers,
      autoDispose: autoDispose,
      enableKeyboard: enableKeyboard,
      focusNode: focusNode,
      onTap: onTap,
      onViewportChanged: onViewportChanged,
      child: child,
    );
  }

  @override
  State<GalileoMapWidget> createState() => _GalileoMapWidgetState();
}

class _GalileoMapWidgetState extends State<GalileoMapWidget>
    with TickerProviderStateMixin {
  GalileoMapState? currentState;
  StreamSubscription<GalileoMapState>? streamSubscription;
  late FocusNode _focusNode;
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  late Ticker panTicker;
  Offset _panAccumulatedDelta = Offset.zero;

  Offset? _lastPointerPosition;
  MapSize? _lastMapSize;
  double _lastPinchScaleValue = 1;
  bool _isPinchScaling = false;

  final Set<int> _activePointers = {};

  /// Lock flags to ensure only one FFI call to getViewport is active at any time.
  bool _isFetchingViewport = false;
  bool _needsViewportUpdate = false;

  /// Fetch the current viewport from Rust and emit it to [onViewportChanged].
  /// Non-blocking/locked: starts the FFI call immediately, and queues at most one
  /// subsequent update if another request comes in while the FFI call is active.
  void _scheduleViewportUpdate() {
    if (widget.onViewportChanged == null) return;
    if (_isFetchingViewport) {
      _needsViewportUpdate = true;
      return;
    }

    _isFetchingViewport = true;
    _needsViewportUpdate = false;

    widget.controller
        .getViewport()
        .then((vp) {
          _isFetchingViewport = false;
          if (vp != null && mounted) {
            widget.onViewportChanged!(vp);
          }
          if (_needsViewportUpdate && mounted) {
            _scheduleViewportUpdate();
          }
        })
        .catchError((e) {
          _isFetchingViewport = false;
          if (_needsViewportUpdate && mounted) {
            _scheduleViewportUpdate();
          }
        });
  }

  double get _devicePixelRatio {
    return MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void initState() {
    super.initState();

    _focusNode = widget.focusNode ?? FocusNode();
    panTicker = createTicker(_onTickPan);

    if (widget.enableKeyboard) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }

    streamSubscription = widget.controller.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          currentState = state;
        });
      }
    });
  }

  void _sendPanEvent(Offset delta, Offset position) {
    final scaleFactor = _devicePixelRatio;
    final panEvent = UserEvent.drag(
      MouseButton.left,
      Vector2(dx: delta.dx * scaleFactor, dy: delta.dy * scaleFactor),
      MouseEvent(
        screenPointerPosition: Point2(
          x: position.dx * scaleFactor,
          y: position.dy * scaleFactor,
        ),
        buttons: const MouseButtonsState(
          left: MouseButtonState.pressed,
          middle: MouseButtonState.released,
          right: MouseButtonState.released,
        ),
      ),
    );
    widget.controller.handleEvent(panEvent);
  }

  void _sendZoomEvent(double zoomFactor, Offset position) {
    final scaleFactor = _devicePixelRatio;
    final zoomEvent = UserEvent.zoom(
      zoomFactor,
      Point2(x: position.dx * scaleFactor, y: position.dy * scaleFactor),
    );
    widget.controller.handleEvent(zoomEvent);
  }

  void _onTickPan(Duration elapsed) {
    if (_panAccumulatedDelta != Offset.zero) {
      _sendPanEvent(_panAccumulatedDelta, _lastPointerPosition!);
      _panAccumulatedDelta = Offset.zero;
      // Schedule a viewport fetch so overlay widgets track the pan in real time.
      _scheduleViewportUpdate();
    }
  }

  Widget _buildLoadingWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            'Error: $message',
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement retry logic in Phase 2
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapWidget(int textureId) {
    Widget mapContent = Stack(
      children: [
        // The actual map texture
        Positioned.fill(child: Texture(textureId: textureId)),
        // Geo-anchored widgets from LayerController
        ListenableBuilder(
          listenable: widget.controller.layerController,
          builder: (context, _) {
            return MapOverlayLayer(
              controller: widget.controller.layerController,
              overlays: widget.controller.layerController.overlays,
            );
          },
        ),
        // Optional child widget overlay
        if (widget.child != null) widget.child!,
      ],
    );
    // Wrap with low-level pointer events for more control
    mapContent = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _activePointers.add(event.pointer);

        if (_activePointers.length > 1 || _isPinchScaling) {
          return;
        }
        // Request focus for keyboard events
        if (widget.enableKeyboard) {
          _focusNode.requestFocus();
        }
        widget.onTap?.call(event.localPosition.dx, event.localPosition.dy);
        _lastPointerPosition = event.localPosition;
        panTicker.start();
      },
      onPointerUp: (event) {
        _activePointers.remove(event.pointer);
        _lastPointerPosition = null;
        panTicker.stop();
        _panAccumulatedDelta = Offset.zero;
      },
      onPointerCancel: (event) {
        _activePointers.remove(event.pointer);
        _lastPointerPosition = null;

        final scaleFactor = _devicePixelRatio;
        // Release button on cancel
        final mouseEvent = UserEvent.buttonReleased(
          MouseButton.left,
          MouseEvent(
            screenPointerPosition: Point2(
              x: event.localPosition.dx * scaleFactor,
              y: event.localPosition.dy * scaleFactor,
            ),
            buttons: const MouseButtonsState(
              left: MouseButtonState.released,
              middle: MouseButtonState.released,
              right: MouseButtonState.released,
            ),
          ),
        );
        widget.controller.handleEvent(mouseEvent);
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          const zoomSensitivity = 0.002;
          final zoomFactor =
              math.pow(1.0 - zoomSensitivity, -event.scrollDelta.dy).toDouble();
          _sendZoomEvent(zoomFactor, event.localPosition);
          _scheduleViewportUpdate();
        }
      },
      onPointerMove: (event) {
        if (_isPinchScaling || _activePointers.length > 1) {
          return;
        }

        if (event.buttons == 0) {
          return;
        }

        final currentPosition = event.localPosition;

        if (_lastPointerPosition case final lastPosition?) {
          final delta = currentPosition - lastPosition;
          _panAccumulatedDelta += delta;
        }

        _lastPointerPosition = currentPosition;
      },
      child: mapContent,
    );
    // Add keyboard support if enabled
    if (widget.enableKeyboard) {
      mapContent = Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: mapContent,
      );
    }

    // Add pinch-to-zoom support
    mapContent = GestureDetector(
      onScaleStart: (details) {
        _lastPinchScaleValue = 1.0;
      },
      onScaleUpdate: (details) {
        if (details.pointerCount >= 2) {
          if (!_isPinchScaling) {
            _isPinchScaling = true;
            _lastPinchScaleValue = details.scale;
            return;
          }

          if (details.scale != _lastPinchScaleValue) {
            final scaleDelta = details.scale / _lastPinchScaleValue;
            const zoomSensitivity = 2.5;
            final amplifiedDelta =
                math.pow(scaleDelta, zoomSensitivity).toDouble();
            _lastPinchScaleValue = details.scale;
            _sendZoomEvent(1.0 / amplifiedDelta, details.localFocalPoint);
            _scheduleViewportUpdate();
          }
        }
      },
      onScaleEnd: (details) {
        _lastPinchScaleValue = 1.0;
        _isPinchScaling = false;
      },
      child: mapContent,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final newMapSize = MapSize(
          width: size.width.toInt(),
          height: size.height.toInt(),
        );

        if (_lastMapSize == null ||
            _lastMapSize!.width != newMapSize.width ||
            _lastMapSize!.height != newMapSize.height) {
          _lastMapSize = newMapSize;
          // resize in next frame
          // TODO: test this
          Future.microtask(() => widget.controller.resize(newMapSize));
        }

        return mapContent;
      },
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    // Handle keyboard events for map navigation only if focused
    if (!_focusNode.hasFocus) return false;

    if (event is KeyDownEvent && !_pressedKeys.contains(event.logicalKey)) {
      _pressedKeys.add(event.logicalKey);
      _handleKeyNavigation(event.logicalKey);
    } else if (event is KeyRepeatEvent &&
        _pressedKeys.contains(event.logicalKey)) {
      _handleKeyNavigation(event.logicalKey);
    } else if (event is KeyUpEvent && _pressedKeys.contains(event.logicalKey)) {
      _pressedKeys.remove(event.logicalKey);
    }
    return false;
  }

  _handleKeyNavigation(LogicalKeyboardKey key) {
    final centerX = widget.controller.size.width / _devicePixelRatio / 2;
    final centerY = widget.controller.size.height / _devicePixelRatio / 2;
    final center = Offset(centerX, centerY);
    const step = 20.0;

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _sendPanEvent(const Offset(0, step), center);
      case LogicalKeyboardKey.arrowDown:
        _sendPanEvent(const Offset(0, -step), center);
      case LogicalKeyboardKey.arrowLeft:
        _sendPanEvent(const Offset(step, 0), center);
      case LogicalKeyboardKey.arrowRight:
        _sendPanEvent(const Offset(-step, 0), center);
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.numpadAdd:
        widget.controller.handleEvent(
          UserEvent.zoom(
            0.9,
            Point2(
              x: centerX * _devicePixelRatio,
              y: centerY * _devicePixelRatio,
            ),
          ),
        );
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        widget.controller.handleEvent(
          UserEvent.zoom(
            1.1,
            Point2(
              x: centerX * _devicePixelRatio,
              y: centerY * _devicePixelRatio,
            ),
          ),
        );
    }
    _scheduleViewportUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (currentState == null) {
      return _buildLoadingWidget('Initializing map...');
    }

    switch (currentState!) {
      case GalileoMapState.initializing:
        return _buildLoadingWidget('Initializing Galileo map...');

      case GalileoMapState.error:
        return _buildErrorWidget('Map encountered an error');

      case GalileoMapState.ready:
        final textureId = widget.controller.textureId;
        if (textureId != null) {
          // Future.microtask(() async => await widget.controller.requestRedraw());
          return _buildMapWidget(textureId);
        } else {
          return _buildLoadingWidget('Preparing texture...');
        }

      case GalileoMapState.stopped:
        return const Center(
          child: Text('Map stopped', style: TextStyle(fontSize: 16)),
        );
    }
  }

  @override
  void dispose() {
    if (widget.enableKeyboard) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }

    super.dispose();

    Future.microtask(() async {
      streamSubscription?.cancel();
      if (widget.autoDispose) {
        try {
          if (kDebugMode) {
            debugPrint(
              'Disposing Galileo map controller (${widget.controller.sessionId})',
            );
          }
          await widget.controller.dispose();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error disposing Galileo map controller: $e');
          }
        }
      }
    });
    // Dispose focus node if we created it
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    panTicker.dispose();
  }
}

class _GalileoMapFromConfig extends StatefulWidget {
  final MapSize size;
  final MapInitConfig config;
  final List<LayerConfig> layers;
  final Widget? child;
  final bool autoDispose;
  final bool enableKeyboard;
  final FocusNode? focusNode;
  final void Function(double x, double y)? onTap;

  /// Called when the map is tapped
  final void Function(MapViewport viewport)? onViewportChanged;

  const _GalileoMapFromConfig({
    super.key,
    required this.size,
    required this.config,
    required this.layers,
    this.child,
    this.autoDispose = true,
    this.enableKeyboard = true,
    this.focusNode,
    this.onTap,
    this.onViewportChanged,
  });

  @override
  State<_GalileoMapFromConfig> createState() => _GalileoMapFromConfigState();
}

class _GalileoMapFromConfigState extends State<_GalileoMapFromConfig> {
  late final Future<(GalileoMapController?, String?)> _controllerFuture;

  @override
  void initState() {
    super.initState();
    _controllerFuture = GalileoMapController.create(
      size: widget.size,
      config: widget.config,
      layers: widget.layers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _controllerFuture,
      builder: (ctx, res) {
        if (res.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (res.hasError) {
          return Center(
            child: Text(
              'Error: ${res.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final (controller, err) = res.data!;
        if (err != null) {
          return Center(
            child: Text(
              'Error: $err',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        return GalileoMapWidget._(
          controller: controller!,
          config: widget.config,
          layers: widget.layers,
          autoDispose: widget.autoDispose,
          enableKeyboard: widget.enableKeyboard,
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          child: widget.child,
        );
      },
    );
  }
}
