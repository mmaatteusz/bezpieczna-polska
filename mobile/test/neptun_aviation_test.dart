import 'package:bezpieczna_polska/neptun_aviation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('map packs only CTR areas for the bundled civil airports', () async {
    final data = await NeptunAviationData.load();
    final airports = (data.airports['features'] as List).cast<Map>();
    final zones = (data.airspace['features'] as List).cast<Map>();
    final ids = {for (final airport in airports) airport['properties']['icao']};
    expect(ids, containsAll(['EPLB', 'EPRZ', 'EPKK']));
    expect(zones, hasLength(airports.length));
    expect({for (final zone in zones) zone['properties']['icao']}, ids);
    expect(
      zones.every((zone) => zone['geometry']['type'] == 'Polygon'),
      isTrue,
    );
    expect(data.bundledTraffic.operations.keys, unorderedEquals(ids));

    final traffic = data.features(
      NeptunAviationLayer.traffic,
      const NeptunTrafficReport('2026-10', {'EPLB': 250, 'EPRZ': 0}),
    );
    final feature = (traffic['features'] as List).single;
    expect(feature['properties']['icao'], 'EPLB');
    expect(feature['properties']['operations'], 250);
  });

  test('Eurostat parser preserves the reporting month and missing entries', () {
    Map<String, dynamic> category(Map<String, int> index) => {
      'category': {'index': index},
    };
    final response = {
      'id': ['freq', 'schedule', 'unit', 'rep_airp', 'time'],
      'size': [1, 1, 1, 2, 2],
      'dimension': {
        'freq': category({'M': 0}),
        'schedule': category({'TOTAL': 0}),
        'unit': category({'NR': 0}),
        'rep_airp': category({'PL_EPRZ': 0, 'PL_EPLB': 1}),
        'time': category({'2026-09': 0, '2026-10': 1}),
      },
      'value': {'0': 800, '1': 710, '2': 190},
    };
    final traffic = NeptunTrafficReport.fromEurostat(response, {
      'EPRZ',
      'EPLB',
    });
    expect(traffic?.period, '2026-10');
    expect(traffic?.operations, {'EPRZ': 710});
    expect(NeptunTrafficReport.fromEurostat(response, {'EPWA'}), isNull);
  });
}
