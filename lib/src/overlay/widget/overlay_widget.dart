import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

enum OverlayType {
  /// Widget's Position stays constant
  static,

  /// Widget's Position is anchored on the Map's Position
  relative,
}

/// Positions a child widget on the map at a given lat/lon coordinate.
///
/// Pushed into [LayerController] via [LayerController.addOverlay].
/// [MapOverlayLayer] inside [GalileoMapWidget] reads the list and
/// repositions each overlay whenever the viewport changes.
class OverlayWidget extends StatelessWidget {
  final Object loc;
  final double height;
  final double width;
  final OverlayType type;
  final Widget child;

  const OverlayWidget._({
    super.key,
    required this.type,
    required this.loc,
    required this.width,
    required this.height,
    required this.child,
  });

  factory OverlayWidget.geo({
    Key? key,
    required GeoLocation loc,
    required double width,
    required double height,
    required Widget child,
  }) => OverlayWidget._(
    key: key,
    type: OverlayType.relative,
    loc: loc,
    width: width,
    height: height,
    child: child,
  );

  factory OverlayWidget.screen({
    Key? key,
    required ScreenLocation loc,
    required double width,
    required double height,
    required Widget child,
  }) => OverlayWidget._(
    key: key,
    type: OverlayType.static,
    loc: loc,
    width: width,
    height: height,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height, child: child);
  }
}
