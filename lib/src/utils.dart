import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Converts a vertex [GeoLocation] to a screen [Offset] in one step.
Offset geoToOffset(GeoLocation geo, Size size, MapViewport vp) {
  final s = geo.toScreen(height: size.height, width: size.width, vp: vp);
  return Offset(s.x, s.y);
}

/// Converts a vertex [Offset] to a screen [Geolocation] in one step.
GeoLocation offsetToGeo(Offset off, Size size, MapViewport vp) {
  final screenLocation = ScreenLocation(x: off.dx, y: off.dy);
  final geoLocation = screenLocation.toGeographical(
    height: size.height,
    width: size.width,
    vp: vp,
  );
  return geoLocation;
}
