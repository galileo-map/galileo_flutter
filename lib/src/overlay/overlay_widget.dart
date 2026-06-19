import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

enum OverlayType {
  /// Size stays constant in screen pixels.
  static,

  /// Size is scaled on the basis of zoom level.
  relative,
}

/// Positions a child widget on the map at a given lat/lon coordinate.
///
/// Pushed into [LayerController] via [LayerController.addOverlay].
/// [MapOverlayLayer] inside [GalileoMapWidget] reads the list and
/// repositions each overlay whenever the viewport changes.
class OverlayWidget extends StatelessWidget {
  final GeoLocation loc;
  final double height;
  final double width;
  final OverlayType type;
  final Widget child;

  const OverlayWidget({
    super.key,
    required this.loc,
    required this.height,
    required this.width,
    required this.type,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height, child: child);
  }
}
