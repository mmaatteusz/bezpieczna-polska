import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

const neptunEmptyFeatures = {
  'type': 'FeatureCollection',
  'features': <Object>[],
};

enum NeptunAviationLayer {
  airports('Lotniska', 'neptun-airports', 'neptun-airport-points'),
  airspace('Strefy CTR', 'neptun-ctr', 'neptun-ctr-fill'),
  traffic('Ruch cywilny', 'neptun-traffic', 'neptun-traffic-circles');

  final String label;
  final String sourceId;
  final String hitLayerId;

  const NeptunAviationLayer(this.label, this.sourceId, this.hitLayerId);
}

class NeptunTrafficReport {
  final String period;
  final Map<String, int> operations;

  const NeptunTrafficReport(this.period, this.operations);

  static NeptunTrafficReport? fromEurostat(
    Map<String, dynamic> data,
    Set<String> airports,
  ) {
    const expectedDimensions = ['freq', 'schedule', 'unit', 'rep_airp', 'time'];
    final ids = data['id'];
    final sizes = data['size'];
    final dimensions = data['dimension'];
    final values = data['value'];
    if (ids is! List ||
        ids.join(',') != expectedDimensions.join(',') ||
        sizes is! List ||
        sizes.length != 5 ||
        sizes.take(3).any((size) => size != 1) ||
        sizes[4] is! int ||
        dimensions is! Map ||
        values is! Map) {
      return null;
    }

    Map? categoryIndex(String dimension) {
      final entry = dimensions[dimension];
      final category = entry is Map ? entry['category'] : null;
      return category is Map && category['index'] is Map
          ? category['index'] as Map
          : null;
    }

    if (categoryIndex('freq')?['M'] != 0 ||
        categoryIndex('schedule')?['TOTAL'] != 0 ||
        categoryIndex('unit')?['NR'] != 0) {
      return null;
    }
    final airportIndex = categoryIndex('rep_airp');
    final timeIndex = categoryIndex('time');
    if (airportIndex == null || timeIndex == null) return null;
    final periods =
        timeIndex.keys
            .whereType<String>()
            .where(RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch)
            .toList()
          ..sort();
    for (final period in periods.reversed) {
      final monthIndex = timeIndex[period];
      if (monthIndex is! int || monthIndex < 0 || monthIndex >= sizes[4]) {
        continue;
      }
      final counts = <String, int>{};
      for (final icao in airports) {
        final index = airportIndex['PL_$icao'];
        if (index is! int || index < 0) continue;
        final value = values['${index * sizes[4] + monthIndex}'];
        if (value is int && value >= 0) counts[icao] = value;
      }
      if (counts.isNotEmpty) return NeptunTrafficReport(period, counts);
    }
    return null;
  }

  static Future<NeptunTrafficReport?> fetch(
    http.Client client,
    Set<String> airports,
  ) async {
    final uri = Uri.https(
      'ec.europa.eu',
      '/eurostat/api/dissemination/statistics/1.0/data/avia_tf_airpm',
      {
        'lang': 'EN',
        'lastTimePeriod': '3',
        'freq': 'M',
        'schedule': 'TOTAL',
        'unit': 'NR',
        'rep_airp': [for (final icao in airports) 'PL_$icao'],
      },
    );
    final response = await client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.length > 64000) {
      return null;
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data is Map<String, dynamic> ? fromEurostat(data, airports) : null;
  }
}

class NeptunAviationData {
  final Map<String, dynamic> countries;
  final Map<String, dynamic> airports;
  final Map<String, dynamic> airspace;
  final NeptunTrafficReport bundledTraffic;
  final String airspaceDate;

  const NeptunAviationData({
    required this.countries,
    required this.airports,
    required this.airspace,
    required this.bundledTraffic,
    required this.airspaceDate,
  });

  static Future<NeptunAviationData> load() async {
    final files = await Future.wait([
      rootBundle.loadString('assets/neptun_aviation.json'),
      rootBundle.loadString('assets/neptun_civil_ctr.geojson'),
    ]);
    final data = jsonDecode(files[0]) as Map<String, dynamic>;
    final airspace = jsonDecode(files[1]) as Map<String, dynamic>;
    final traffic = data['traffic'] as Map;
    return NeptunAviationData(
      countries: data['countries'] as Map<String, dynamic>,
      airports: data['airports'] as Map<String, dynamic>,
      airspace: airspace,
      bundledTraffic: NeptunTrafficReport(
        traffic['period'] as String,
        (traffic['operations'] as Map).cast<String, int>(),
      ),
      airspaceDate: (airspace['metadata']['date'] as String)
          .split('-')
          .reversed
          .join('.'),
    );
  }

  Map<String, dynamic> features(
    NeptunAviationLayer layer,
    NeptunTrafficReport traffic,
  ) {
    switch (layer) {
      case NeptunAviationLayer.airports:
        return airports;
      case NeptunAviationLayer.airspace:
        return airspace;
      case NeptunAviationLayer.traffic:
        return {
          'type': 'FeatureCollection',
          'features': [
            for (final airport in (airports['features'] as List).cast<Map>())
              if (traffic.operations[airport['properties']['icao']]
                  case final int operations when operations > 0)
                {
                  ...airport,
                  'properties': {
                    ...airport['properties'] as Map,
                    'operations': operations,
                  },
                },
          ],
        };
    }
  }
}

Future<void> addNeptunAviationLayers(
  MapLibreMapController controller,
  NeptunAviationData data,
  Set<NeptunAviationLayer> enabled,
  NeptunTrafficReport traffic,
) async {
  final baseLayers = await controller.getLayerIds();
  final underLabels = baseLayers.contains('water_name') ? 'water_name' : null;
  const countries = 'neptun-countries';
  await controller.addSource(
    countries,
    GeojsonSourceProperties(data: data.countries),
  );
  await controller.addFillLayer(
    countries,
    'neptun-country-colors',
    const FillLayerProperties(
      fillColor: ['get', 'color'],
      fillOpacity: [
        'interpolate',
        ['linear'],
        ['zoom'],
        4,
        0.54,
        6,
        0.44,
        9,
        0.14,
        11,
        0,
      ],
    ),
    belowLayerId: underLabels,
  );

  for (final layer in NeptunAviationLayer.values) {
    await controller.addSource(
      layer.sourceId,
      GeojsonSourceProperties(
        data: enabled.contains(layer)
            ? data.features(layer, traffic)
            : neptunEmptyFeatures,
      ),
    );
  }

  const ctr = NeptunAviationLayer.airspace;
  await controller.addFillLayer(
    ctr.sourceId,
    ctr.hitLayerId,
    const FillLayerProperties(fillColor: '#f1ad48', fillOpacity: 0.21),
  );
  await controller.addLineLayer(
    ctr.sourceId,
    'neptun-ctr-outline',
    const LineLayerProperties(
      lineColor: '#ffc56a',
      lineOpacity: 0.82,
      lineWidth: 1.5,
    ),
  );

  const civil = NeptunAviationLayer.traffic;
  await controller.addCircleLayer(
    civil.sourceId,
    civil.hitLayerId,
    const CircleLayerProperties(
      circleRadius: [
        'interpolate',
        ['linear'],
        ['get', 'operations'],
        0,
        7,
        300,
        11,
        1000,
        17,
        4500,
        26,
        13000,
        35,
      ],
      circleColor: '#3bd2bc',
      circleOpacity: 0.30,
      circleStrokeColor: '#75ecdb',
      circleStrokeOpacity: 0.75,
      circleStrokeWidth: 1.15,
    ),
  );

  const airport = NeptunAviationLayer.airports;
  await controller.addCircleLayer(
    airport.sourceId,
    airport.hitLayerId,
    const CircleLayerProperties(circleRadius: 17, circleOpacity: 0.001),
  );
  await controller.addCircleLayer(
    airport.sourceId,
    'neptun-airport-dots',
    const CircleLayerProperties(
      circleColor: '#aedefc',
      circleRadius: 4.7,
      circleStrokeWidth: 1.5,
      circleStrokeColor: '#153550',
    ),
  );
  await controller.addSymbolLayer(
    airport.sourceId,
    'neptun-airport-codes',
    const SymbolLayerProperties(
      textField: ['get', 'iata'],
      textFont: ['Noto Sans Regular'],
      textAnchor: 'left',
      textOffset: [0.72, 0],
      textSize: 11,
      textColor: '#e6f5ff',
      textHaloColor: '#13212d',
      textHaloWidth: 1.65,
    ),
    minzoom: 5,
  );
}
