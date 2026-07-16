import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Positions a child widget on the map at a given lat/lon coordinate.
///
/// Pushed into [LayerController] via [LayerController.addOverlay].
/// [MapOverlayLayer] inside [GalileoMapWidget] reads the list and
/// repositions each overlay whenever the viewport changes.
class OverlayWidget extends StatelessWidget {
  final GeoLocation loc;
  final double height;
  final double width;
  final Widget child;

  /// Minimum zoom scale at which this overlay becomes visible.
  /// Uses the relative scale from [LayerController.zoomScale] (1.0 = initial).
  /// If null, the overlay is visible at all zoom-out levels.
  final double? minZoom;

  /// Maximum zoom scale at which this overlay remains visible.
  /// If null, the overlay is visible at all zoom-in levels.
  final double? maxZoom;

  const OverlayWidget._({
    super.key,
    required this.loc,
    required this.width,
    required this.height,
    this.minZoom,
    this.maxZoom,
    required this.child,
  });

  factory OverlayWidget.geo({
    Key? key,
    required GeoLocation loc,
    required double width,
    required double height,
    double? minZoom,
    double? maxZoom,
    required Widget child,
  }) => OverlayWidget._(
    key: key,
    loc: loc,
    width: width,
    height: height,
    minZoom: minZoom,
    maxZoom: maxZoom,
    child: child,
  );

  /// Whether this overlay should be visible at the given [zoomScale].
  bool isVisibleAt(double zoomScale) {
    if (minZoom != null && zoomScale < minZoom!) return false;
    if (maxZoom != null && zoomScale > maxZoom!) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height, child: child);
  }
}
