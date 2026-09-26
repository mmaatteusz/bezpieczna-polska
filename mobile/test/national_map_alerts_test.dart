import 'package:bezpieczna_polska/map_layers.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:flutter_test/flutter_test.dart';

SafetyEvent eventFixture({
  required String id,
  required List<String> regions,
  double? latitude,
  double? longitude,
  DateTime? validTo,
  String sourceId = 'RCB',
}) {
  return SafetyEvent({
    'id': id,
    'title': 'Alert testowy',
    'description': 'Test mapy.',
    'revision': 1,
    'regions': regions,
    'sources': [
      {
        'id': sourceId,
        'name': sourceId.startsWith('IMGW')
            ? 'IMGW-PIB'
            : 'Rządowe Centrum Bezpieczeństwa',
        'url': 'https://www.gov.pl/web/rcb',
        'tier': 1,
      },
    ],
    'lifecycle': 'ACTIVE',
    'messageContext': 'ACTUAL',
    'verification': 'CONFIRMED',
    'validTo': validTo?.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
  });
}

void main() {
  final now = DateTime.utc(2026, 9, 26, 10);

  test('regional RCB alert without coordinates gets overview markers', () {
    final event = eventFixture(
      id: 'RCB-regional',
      regions: ['04', '14'],
      validTo: now.add(const Duration(hours: 2)),
    );

    final features = mapEventFeatures(event, now);

    expect(features, hasLength(2));
    expect(
      features.map((feature) => feature['properties']['regionId']).toSet(),
      {'04', '14'},
    );
    expect(
      features.every(
        (feature) => feature['properties']['mapLocationKind'] == 'REGION_SCOPE',
      ),
      isTrue,
    );
  });

  test('event with coordinates keeps its real point', () {
    final event = eventFixture(
      id: 'point-event',
      regions: ['04'],
      latitude: 53.1,
      longitude: 18.2,
      validTo: now.add(const Duration(hours: 2)),
    );

    final features = mapEventFeatures(event, now);

    expect(features, hasLength(1));
    expect(features.single['geometry']['coordinates'], [18.2, 53.1]);
    expect(features.single['properties']['mapLocationKind'], 'EVENT_POINT');
    expect(features.single['properties']['mapCategory'], 'ALERT');
  });

  test('IMGW meteo and hydro warnings use the blue map layer', () {
    for (final sourceId in ['IMGW_METEO', 'IMGW_HYDRO']) {
      final event = eventFixture(
        id: 'imgw-event-$sourceId',
        regions: ['04'],
        validTo: now.add(const Duration(hours: 2)),
        sourceId: sourceId,
      );

      final features = mapEventFeatures(event, now);

      expect(features, isNotEmpty);
      expect(
        features.every(
          (feature) => feature['properties']['mapCategory'] == 'IMGW',
        ),
        isTrue,
      );
      expect(mapEventIsImgw(event), isTrue);
    }
  });

  test('expired event is not rendered on overview map', () {
    final event = eventFixture(
      id: 'expired-event',
      regions: ['04'],
      validTo: now.subtract(const Duration(seconds: 1)),
    );

    expect(mapEventFeatures(event, now), isEmpty);
  });
}
