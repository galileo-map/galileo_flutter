import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:latlong2/latlong.dart';

extension GalileoCoordinateExt on LatLng {
  GeoLocation toGalileo() {
    return GeoLocation(latitude: latitude, longitude: longitude);
  }
}
