import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Converts a vertex [GeoLocation] to a screen [Offset] in one step.
Offset geoToOffset(GeoLocation geo, Size size, MapViewport vp) {
  final s = geo.toScreen(height: size.height, width: size.width, vp: vp);
  return Offset(s.x, s.y);
}
