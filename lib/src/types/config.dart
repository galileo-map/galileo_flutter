import 'package:latlong2/latlong.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart';

extension LatLngToMapPosition on LatLng {
  MapPosition toMapPosition() =>
      MapPosition(latitude: latitude, longitude: longitude);
}

extension MapPositionToLatLng on MapPosition {
  LatLng toLatLng() => LatLng(latitude, longitude);
}

extension LatLngListToMapPositions on List<LatLng> {
  List<MapPosition> toMapPositions() => map((p) => p.toMapPosition()).toList();
}
