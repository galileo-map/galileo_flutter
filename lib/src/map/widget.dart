import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galileo_flutter/src/map/controller.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart';
import 'package:galileo_flutter/src/layer/overlay/overlay.dart';

final _log = Logger('GalileoMapWidget');

/// A widget that displays a Galileo map with interactive controls
/// Degrees of rotation per physical pixel of a secondary-button mouse drag.
const double _kRotateDegreesPerPixel = 0.5;

/// Degrees of tilt per physical pixel of vertical drag (mouse or two fingers).
const double _kPitchDegreesPerPixel = 0.25;

/// A two-finger gesture counts as zoom/rotate once the fingers' spread
/// (natural-log scale) or twist (radians) travels this far...
const double _kGestureScaleSlop = 0.03;
const double _kGestureRotationSlop = 0.06;

/// ...and as a tilt once both fingers slid this many logical pixels vertically
/// (and mostly vertically) without spreading or twisting first.
const double _kGestureTiltSlop = 8;

/// Twist (radians) the fingers must accumulate before the map starts rotating,
/// so an ordinary pinch-zoom does not wobble the bearing.
const double _kRotationDeadband = 0.12;

enum _TwoFingerMode { undecided, tilt, transform }

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

class _GalileoMapWidgetState extends State<GalileoMapWidget> {
  GalileoMapState? currentState;
  StreamSubscription<GalileoMapState>? streamSubscription;
  StreamSubscription<MapViewport>? viewportSubscription;
  late FocusNode _focusNode;
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  Offset? _lastPointerPosition;
  MapSize? _lastMapSize;
  Timer? resizeTimer;
  double _lastPinchScaleValue = 1;
  bool _isPinchScaling = false;

  /// True while a secondary mouse button drag rotates and tilts the map.
  bool _isOrientDragging = false;

  // Two-finger gesture state. A gesture is either a tilt (both fingers sliding
  // vertically together) or a zoom/rotate; it is decided from the first few
  // frames of movement and then latched.
  _TwoFingerMode _twoFingerMode = _TwoFingerMode.undecided;
  double _pinchStartScale = 1;
  double _rotationStart = 0;
  Offset _twoFingerFocalTravel = Offset.zero;
  double _lastRotation = 0;
  bool _isRotating = false;

  final Set<int> _activePointers = {};

  double get _devicePixelRatio {
    return MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void initState() {
    super.initState();

    _focusNode = widget.focusNode ?? FocusNode();

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
    widget.controller.textureIdListenable.addListener(_handleTextureIdChanged);
    viewportSubscription = widget.controller.renderedViewportStream.listen((
      vp,
    ) {
      if (mounted) widget.onViewportChanged?.call(vp);
    });
  }

  void _handleTextureIdChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendPanEvent(
    Offset delta,
    Offset position,
    Duration timestamp,
  ) {
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
        timestampMicros: BigInt.from(timestamp.inMicroseconds),
      ),
    );
    return widget.controller.handleEvent(panEvent);
  }

  Future<void> _sendPointerPressed(Offset position, Duration timestamp) {
    final scaleFactor = _devicePixelRatio;
    return widget.controller.handleEvent(
      UserEvent.buttonPressed(
        MouseButton.left,
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
          timestampMicros: BigInt.from(timestamp.inMicroseconds),
        ),
      ),
    );
  }

  Future<void> _sendPointerReleased(Offset position, Duration timestamp) {
    final scaleFactor = _devicePixelRatio;
    return widget.controller.handleEvent(
      UserEvent.buttonReleased(
        MouseButton.left,
        MouseEvent(
          screenPointerPosition: Point2(
            x: position.dx * scaleFactor,
            y: position.dy * scaleFactor,
          ),
          buttons: const MouseButtonsState(
            left: MouseButtonState.released,
            middle: MouseButtonState.released,
            right: MouseButtonState.released,
          ),
          timestampMicros: BigInt.from(timestamp.inMicroseconds),
        ),
      ),
    );
  }

  /// Sends a zoom event to Rust. Overlay updates arrive with the rendered frame.
  Future<void> _sendZoomEvent(
    double zoomFactor,
    Offset position, {
    bool direct = false,
  }) {
    final scaleFactor = _devicePixelRatio;
    final point = Point2(
      x: position.dx * scaleFactor,
      y: position.dy * scaleFactor,
    );
    final zoomEvent = direct
        ? UserEvent.zoomImmediate(zoomFactor, point)
        : UserEvent.zoomAnimated(zoomFactor, point);
    return widget.controller.handleEvent(zoomEvent);
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
          listenable: widget.controller.layerController.overlaysRevision,
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
        _lastPointerPosition = event.localPosition;
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons & kSecondaryMouseButton != 0) {
          _isOrientDragging = true;
          return;
        }
        widget.onTap?.call(event.localPosition.dx, event.localPosition.dy);
        // A touch-down stops any fling in progress.
        _sendPointerPressed(event.localPosition, event.timeStamp);
      },
      onPointerUp: (event) {
        if (_isOrientDragging) {
          _isOrientDragging = false;
          _activePointers.remove(event.pointer);
          _lastPointerPosition = null;
          return;
        }
        final wasPanning = _activePointers.length == 1 && !_isPinchScaling;
        _activePointers.remove(event.pointer);
        // Tell the map the button went up so it can fling with the drag's velocity.
        if (wasPanning &&
            _lastPointerPosition != null &&
            !widget.controller.layerController.shouldSuppressPan) {
          _sendPointerReleased(event.localPosition, event.timeStamp);
        }
        _lastPointerPosition = null;
      },
      onPointerCancel: (event) {
        _isOrientDragging = false;
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
            timestampMicros: BigInt.from(event.timeStamp.inMicroseconds),
          ),
        );
        widget.controller.handleEvent(mouseEvent);
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          const zoomSensitivity = 0.002;
          final zoomFactor = math
              .pow(1.0 - zoomSensitivity, -event.scrollDelta.dy)
              .toDouble();
          _sendZoomEvent(zoomFactor, event.localPosition);
        }
      },
      onPointerMove: (event) {
        if (_isPinchScaling || _activePointers.length > 1) {
          return;
        }

        if (event.buttons == 0) {
          return;
        }

        if (_isOrientDragging) {
          // Secondary-button drag: horizontal rotates, vertical tilts.
          final scale = _devicePixelRatio;
          final size = widget.controller.size;
          final delta = event.delta * scale;
          if (delta.dx != 0) {
            widget.controller.handleEvent(
              UserEvent.rotate(
                delta.dx * _kRotateDegreesPerPixel,
                Point2(x: size.width / 2, y: size.height / 2),
              ),
            );
          }
          if (delta.dy != 0) {
            widget.controller.handleEvent(
              UserEvent.pitch(-delta.dy * _kPitchDegreesPerPixel),
            );
          }
          return;
        }

        // If an overlay suppresses panning, keep the next drag anchored at
        // the current pointer position.
        if (widget.controller.layerController.shouldSuppressPan) {
          _lastPointerPosition = event.localPosition;
          return;
        }

        final currentPosition = event.localPosition;

        if (_lastPointerPosition case final lastPosition?) {
          final delta = currentPosition - lastPosition;
          if (delta != Offset.zero) {
            _sendPanEvent(delta, currentPosition, event.timeStamp);
          }
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
        _lastRotation = 0;
        _isRotating = false;
        _twoFingerMode = _TwoFingerMode.undecided;
        _pinchStartScale = 1;
        _rotationStart = 0;
        _twoFingerFocalTravel = Offset.zero;
      },
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: (details) {
        _lastPinchScaleValue = 1.0;
        _lastRotation = 0;
        _isRotating = false;
        _isPinchScaling = false;
        _twoFingerMode = _TwoFingerMode.undecided;
      },
      child: mapContent,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = _devicePixelRatio;
        final newMapSize = MapSize(
          width: (size.width * scale).round(),
          height: (size.height * scale).round(),
        );

        if (_lastMapSize == null ||
            _lastMapSize!.width != newMapSize.width ||
            _lastMapSize!.height != newMapSize.height) {
          _lastMapSize = newMapSize;
          resizeTimer?.cancel();
          resizeTimer = Timer(const Duration(milliseconds: 50), () {
            if (mounted) {
              widget.controller.resize(newMapSize);
            }
          });
        }

        return mapContent;
      },
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    if (!_isPinchScaling) {
      _isPinchScaling = true;
      _lastPinchScaleValue = details.scale;
      _lastRotation = details.rotation;
      _pinchStartScale = details.scale;
      _rotationStart = details.rotation;
      return;
    }

    final scaleDelta = details.scale / _lastPinchScaleValue;
    var rotationDelta = details.rotation - _lastRotation;
    _lastPinchScaleValue = details.scale;
    _lastRotation = details.rotation;
    _twoFingerFocalTravel += details.focalPointDelta;

    if (_twoFingerMode == _TwoFingerMode.undecided) {
      final focal = _twoFingerFocalTravel;
      final isSpreading =
          math.log(details.scale / _pinchStartScale).abs() >
              _kGestureScaleSlop ||
          (details.rotation - _rotationStart).abs() > _kGestureRotationSlop;
      if (isSpreading) {
        _twoFingerMode = _TwoFingerMode.transform;
      } else if (focal.dy.abs() > _kGestureTiltSlop &&
          focal.dy.abs() > 2 * focal.dx.abs()) {
        _twoFingerMode = _TwoFingerMode.tilt;
        // Apply the movement accumulated while deciding.
        _sendPitchEvent(-focal.dy);
        return;
      } else {
        return;
      }
    }

    if (_twoFingerMode == _TwoFingerMode.tilt) {
      _sendPitchEvent(-details.focalPointDelta.dy);
      return;
    }

    final focal = details.localFocalPoint;
    final rotationTotal = (details.rotation - _rotationStart).abs();
    if (!_isRotating && rotationTotal > _kRotationDeadband) {
      // Past the dead band: start rotating from here so the map does not jump.
      _isRotating = true;
      rotationDelta = 0;
    }
    if (_isRotating) {
      if (rotationDelta != 0) {
        final scale = _devicePixelRatio;
        widget.controller.handleEvent(
          UserEvent.rotate(
            rotationDelta * 180 / math.pi,
            Point2(x: focal.dx * scale, y: focal.dy * scale),
          ),
        );
      }
    }
    if (scaleDelta != 1.0) {
      const zoomSensitivity = 2.5;
      final amplifiedDelta = math.pow(scaleDelta, zoomSensitivity).toDouble();
      _sendZoomEvent(1.0 / amplifiedDelta, focal, direct: true);
    }
  }

  /// Tilts the map for a vertical two-finger movement of [dy] logical pixels
  /// (positive tilts towards the horizon).
  void _sendPitchEvent(double dy) {
    if (dy == 0) return;
    widget.controller.handleEvent(
      UserEvent.pitch(dy * _devicePixelRatio * _kPitchDegreesPerPixel),
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

  Future<void> _handleKeyNavigation(LogicalKeyboardKey key) async {
    final centerX = widget.controller.size.width / _devicePixelRatio / 2;
    final centerY = widget.controller.size.height / _devicePixelRatio / 2;
    final center = Offset(centerX, centerY);
    const step = 20.0;

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        await _sendPanEvent(const Offset(0, step), center, Duration.zero);
      case LogicalKeyboardKey.arrowDown:
        await _sendPanEvent(const Offset(0, -step), center, Duration.zero);
      case LogicalKeyboardKey.arrowLeft:
        await _sendPanEvent(const Offset(step, 0), center, Duration.zero);
      case LogicalKeyboardKey.arrowRight:
        await _sendPanEvent(const Offset(-step, 0), center, Duration.zero);

      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.numpadAdd:
        await widget.controller.handleEvent(
          UserEvent.zoomAnimated(
            0.9,
            Point2(
              x: centerX * _devicePixelRatio,
              y: centerY * _devicePixelRatio,
            ),
          ),
        );
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        await widget.controller.handleEvent(
          UserEvent.zoomAnimated(
            1.1,
            Point2(
              x: centerX * _devicePixelRatio,
              y: centerY * _devicePixelRatio,
            ),
          ),
        );
    }
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

    resizeTimer?.cancel();
    widget.controller.textureIdListenable.removeListener(
      _handleTextureIdChanged,
    );
    super.dispose();

    Future.microtask(() async {
      streamSubscription?.cancel();
      viewportSubscription?.cancel();
      if (widget.autoDispose) {
        try {
          _log.info(
            'Disposing Galileo map controller (${widget.controller.sessionId})',
          );
          await widget.controller.dispose();
        } catch (e) {
          _log.severe('Error disposing Galileo map controller', e);
        }
      }
    });
    // Dispose focus node if we created it
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
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
