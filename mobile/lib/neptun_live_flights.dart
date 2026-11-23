import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'neptun_aviation.dart' show neptunEmptyFeatures;

const neptunLiveFlightsUrl = 'https://www.flightradar24.com/49.8,27.5/5';
const neptunLiveFlightsSource = 'neptun-live-flights';
const neptunLiveFlightsLayer = 'neptun-passenger-planes';

const neptunFlightCountries = {
  'PL': 'Polska',
  'SK': 'Słowacja',
  'HU': 'Węgry',
  'RO': 'Rumunia',
  'MD': 'Mołdawia',
  'BY': 'Białoruś',
  'RU': 'Rosja',
};

enum NeptunLiveFlightsState { live, notConfigured, unavailable }

class NeptunLiveFlight {
  final String id, number, country;
  final double latitude, longitude;
  final int track, altitudeFt, speedKt;
  final DateTime observedAt;
  final String? from, to;

  const NeptunLiveFlight({
    required this.id,
    required this.number,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.track,
    required this.altitudeFt,
    required this.speedKt,
    required this.observedAt,
    required this.from,
    required this.to,
  });

  factory NeptunLiveFlight.parse(Object? value) {
    if (value
        case {
          'id': final String id,
          'number': final String number,
          'country': final String country,
          'latitude': final num latitude,
          'longitude': final num longitude,
          'track': final int track,
          'altitudeFt': final int altitudeFt,
          'speedKt': final int speedKt,
          'observedAt': final String observedAt,
          'from': final String? from,
          'to': final String? to,
        }
        when id.isNotEmpty &&
            number.isNotEmpty &&
            neptunFlightCountries.containsKey(country) &&
            latitude.abs() <= 90 &&
            longitude.abs() <= 180 &&
            track >= 0 &&
            track < 360) {
      return NeptunLiveFlight(
        id: id,
        number: number,
        country: country,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        track: track,
        altitudeFt: altitudeFt,
        speedKt: speedKt,
        observedAt: DateTime.parse(observedAt),
        from: from,
        to: to,
      );
    }
    throw const FormatException('Niepoprawna pozycja lotu');
  }

  Map<String, dynamic> get feature => {
    'type': 'Feature',
    'id': id,
    'geometry': {
      'type': 'Point',
      'coordinates': [longitude, latitude],
    },
    'properties': {'flightId': id, 'track': track},
  };
}

class NeptunLiveFlights {
  final NeptunLiveFlightsState state;
  final DateTime? checkedAt;
  final bool limitReached;
  final Map<String, NeptunLiveFlight> flights;

  const NeptunLiveFlights(
    this.state, {
    this.checkedAt,
    this.limitReached = false,
    this.flights = const {},
  });

  factory NeptunLiveFlights.parse(Object? value) {
    return switch (value) {
      {'state': 'NOT_CONFIGURED', 'flights': []} => const NeptunLiveFlights(
        NeptunLiveFlightsState.notConfigured,
      ),
      {'state': 'UNAVAILABLE', 'flights': []} => const NeptunLiveFlights(
        NeptunLiveFlightsState.unavailable,
      ),
      {
        'state': 'LIVE',
        'checkedAt': final String checkedAt,
        'limitReached': final bool limitReached,
        'flights': final List flights,
      }
          when flights.length <= 300 =>
        NeptunLiveFlights(
          NeptunLiveFlightsState.live,
          checkedAt: DateTime.parse(checkedAt),
          limitReached: limitReached,
          flights: {
            for (final flight in flights.map(NeptunLiveFlight.parse))
              flight.id: flight,
          },
        ),
      _ => throw const FormatException('Niepoprawne dane o lotach'),
    };
  }

  Map<String, dynamic> get map => {
    'type': 'FeatureCollection',
    'features': [for (final flight in flights.values) flight.feature],
  };
}

Future<void> addNeptunLiveFlightsLayer(MapLibreMapController controller) async {
  const imageId = 'neptun-passenger-plane';
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final plane = Path()
    ..moveTo(12, 2)
    ..quadraticBezierTo(14, 2, 14, 8)
    ..lineTo(22, 13)
    ..lineTo(22, 16)
    ..lineTo(14, 13)
    ..lineTo(14, 18)
    ..lineTo(17, 20)
    ..lineTo(17, 22)
    ..lineTo(12, 21)
    ..lineTo(7, 22)
    ..lineTo(7, 20)
    ..lineTo(10, 18)
    ..lineTo(10, 13)
    ..lineTo(2, 16)
    ..lineTo(2, 13)
    ..lineTo(10, 8)
    ..quadraticBezierTo(10, 2, 12, 2)
    ..close();
  canvas.drawPath(
    plane,
    Paint()
      ..color = const Color(0xff182815)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(plane, Paint()..color = const Color(0xffd4fa86));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(24, 24);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Nie udało się utworzyć ikony lotu');
      await controller.addImage(imageId, png.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
  await controller.addSource(
    neptunLiveFlightsSource,
    const GeojsonSourceProperties(data: neptunEmptyFeatures),
  );
  await controller.addSymbolLayer(
    neptunLiveFlightsSource,
    neptunLiveFlightsLayer,
    const SymbolLayerProperties(
      iconImage: imageId,
      iconSize: [
        'interpolate',
        ['linear'],
        ['zoom'],
        4,
        0.75,
        7,
        1,
      ],
      iconRotate: ['get', 'track'],
      iconRotationAlignment: 'map',
      iconAllowOverlap: true,
    ),
  );
}
