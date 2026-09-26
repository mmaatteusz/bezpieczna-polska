import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Lets an embedded native map win the gesture arena against surrounding
/// scroll views. Without this, vertical and diagonal drags can feel sticky.
Set<Factory<OneSequenceGestureRecognizer>> mapGestureRecognizers() =>
    <Factory<OneSequenceGestureRecognizer>>{
      Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
    };

String shelterNavigationUrl({
  required double latitude,
  required double longitude,
}) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    throw ArgumentError('Niepoprawne współrzędne schronienia');
  }
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$latitude,$longitude',
    'travelmode': 'driving',
    'dir_action': 'navigate',
  }).toString();
}
