import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

const double _kMercatorRadius = 6378137.0;

/// Converts a vertex [GeoLocation] to a screen [Offset] in one step.
///
/// Bit-identical port of the Rust `GeoLocation::to_screen` implementation so
/// hot rendering paths can project points without crossing the FFI boundary.
Offset geoToOffset(GeoLocation geo, Size size, MapViewport vp) {
  final latRad = geo.latitude * math.pi / 180.0;
  final mx = geo.longitude * math.pi / 180.0 * _kMercatorRadius;
  final my =
      math.log(math.tan(math.pi / 4.0 + latRad / 2.0)) * _kMercatorRadius;
  final dx = vp.xMax - vp.xMin;
  final dy = vp.yMax - vp.yMin;
  return Offset(
    dx == 0.0 ? 0.0 : (mx - vp.xMin) / dx * size.width,
    dy == 0.0 ? 0.0 : (vp.yMax - my) / dy * size.height,
  );
}

/// Projects many vertices to screen offsets in one pass.
List<Offset> geosToOffsets(List<GeoLocation> geos, Size size, MapViewport vp) {
  return List<Offset>.generate(
    geos.length,
    (i) => geoToOffset(geos[i], size, vp),
    growable: false,
  );
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
