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

  test('IMGW TERYT warning is placed at affected powiats', () {
    final event = SafetyEvent({
      ...eventFixture(
        id: 'imgw-teryt',
        regions: ['04', '14'],
        validTo: now.add(const Duration(hours: 2)),
        sourceId: 'IMGW_METEO',
      ).data,
      'locationText': 'TERYT: 0403, 1465',
      'areaPrecision': 'PROVINCE_SUBSET',
    });

    final features = mapEventFeatures(
      event,
      now,
      administrativeAnchors: const {
        '0403': [18.6, 53.0],
        '1465': [21.0, 52.2],
      },
    );

    expect(features, hasLength(2));
    expect(
      features.map((feature) => feature['geometry']['coordinates']).toSet(),
      {
        [18.6, 53.0],
        [21.0, 52.2],
      },
    );
    expect(
      features.every(
        (feature) =>
            feature['properties']['mapLocationKind'] == 'TERYT_SCOPE',
      ),
      isTrue,
    );
  });

  test('missing TERYT centroid falls back to its voivodeship anchor', () {
    final event = SafetyEvent({
      ...eventFixture(
        id: 'imgw-teryt-fallback',
        regions: ['04'],
        validTo: now.add(const Duration(hours: 2)),
        sourceId: 'IMGW_METEO',
      ).data,
      'locationText': 'TERYT: 0403',
      'areaPrecision': 'PROVINCE_SUBSET',
    });

    final features = mapEventFeatures(event, now);

    expect(features, hasLength(1));
    expect(features.single['geometry']['coordinates'], mapRegionAnchors['04']);
    expect(features.single['properties']['mapLocationKind'], 'REGION_SCOPE');
  });

  test('overlapping alert and IMGW markers are marked for deconfliction', () {
    final alert = mapEventFeatures(
      eventFixture(
        id: 'alert-overlap',
        regions: ['04'],
        validTo: now.add(const Duration(hours: 2)),
      ),
      now,
    ).single;
    final imgw = mapEventFeatures(
      eventFixture(
        id: 'imgw-overlap',
        regions: ['04'],
        validTo: now.add(const Duration(hours: 2)),
        sourceId: 'IMGW_METEO',
      ),
      now,
    ).single;

    final features = markMapCategoryCollisions([alert, imgw]);

    expect(
      features.every(
        (feature) => feature['properties']['mapCollision'] == true,
      ),
      isTrue,
    );
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

  test('IMGW visibility can be toggled independently from other events', () {
    final imgw = eventFixture(
      id: 'imgw-toggle',
      regions: ['04'],
      validTo: now.add(const Duration(hours: 2)),
      sourceId: 'IMGW_METEO',
    );
    final rcb = eventFixture(
      id: 'rcb-toggle',
      regions: ['04'],
      validTo: now.add(const Duration(hours: 2)),
    );

    expect(
      mapEventVisibleForLayers(imgw, showEvents: true, showImgw: false),
      isFalse,
    );
    expect(
      mapEventVisibleForLayers(rcb, showEvents: true, showImgw: false),
      isTrue,
    );
    expect(
      mapEventVisibleForLayers(imgw, showEvents: false, showImgw: true),
      isTrue,
    );
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
