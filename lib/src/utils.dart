import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

const double _kMercatorRadius = 6378137.0;

/// MapLibre's default field of view puts the camera this many screen heights
/// from the map center.
const double _kCameraDistancePerHeight = 1.5;
const double _kOffscreen = -1.0e7;

/// Converts a vertex [GeoLocation] to a screen [Offset] in one step.
///
/// Port of the Rust `GeoLocation::to_screen` implementation (including the
/// bearing and pitch carried by [vp]) so hot rendering paths can project points
/// without crossing the FFI boundary. Points behind the camera land far
/// off-screen.
Offset geoToOffset(GeoLocation geo, Size size, MapViewport vp) {
  final latRad = geo.latitude * math.pi / 180.0;
  final mx = geo.longitude * math.pi / 180.0 * _kMercatorRadius;
  final my =
      math.log(math.tan(math.pi / 4.0 + latRad / 2.0)) * _kMercatorRadius;
  final span = vp.xMax - vp.xMin;
  final scale = span == 0.0 ? 0.0 : size.width / span;
  final east = (mx - (vp.xMin + vp.xMax) / 2.0) * scale;
  final south = -(my - (vp.yMin + vp.yMax) / 2.0) * scale;

  if (vp.bearing == 0.0 && vp.pitch == 0.0) {
    return Offset(size.width / 2.0 + east, size.height / 2.0 + south);
  }

  final bearing = vp.bearing * math.pi / 180.0;
  final pitch = vp.pitch * math.pi / 180.0;
  final x = east * math.cos(bearing) + south * math.sin(bearing);
  final y = -east * math.sin(bearing) + south * math.cos(bearing);
  final distance = _kCameraDistancePerHeight * size.height;
  final depth = distance - y * math.sin(pitch);
  if (depth <= 1e-6) {
    return const Offset(_kOffscreen, _kOffscreen);
  }
  final k = distance / depth;
  return Offset(
    size.width / 2.0 + x * k,
    size.height / 2.0 + y * math.cos(pitch) * k,
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
