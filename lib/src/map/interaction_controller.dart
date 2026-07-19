import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Coordinates pointer ownership between map overlays and map gestures.
///
/// An overlay calls [consume] when it handles a pointer down. The map then
/// suppresses panning and map taps for that pointer until [complete] or
/// [cancel] is called by the map's top-level listener.
class MapInteractionController {
  MapInteractionController({this.tapThreshold = 10.0});

  final double tapThreshold;
  final Map<int, Offset> _pointerDownPositions = {};
  final Set<int> _consumedPointers = {};

  void begin(PointerDownEvent event) {
    _pointerDownPositions[event.pointer] = event.localPosition;
  }

  /// Marks [pointer] as handled by an overlay for the rest of its gesture.
  void consume(int pointer) {
    _consumedPointers.add(pointer);
  }

  bool isConsumed(int pointer) => _consumedPointers.contains(pointer);

  /// Returns whether [event] completes an unconsumed tap, then clears state.
  bool complete(PointerUpEvent event) {
    final down = _pointerDownPositions.remove(event.pointer);
    final consumed = _consumedPointers.remove(event.pointer);
    return !consumed &&
        down != null &&
        (event.localPosition - down).distance < tapThreshold;
  }

  void cancel(PointerCancelEvent event) {
    _pointerDownPositions.remove(event.pointer);
    _consumedPointers.remove(event.pointer);
  }
}
