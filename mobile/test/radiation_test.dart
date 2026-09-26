import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/radiation.dart';
import 'package:bezpieczna_polska/model.dart';

Map<String, dynamic> radiation(DateTime now) => {
  'schemaVersion': 1,
  'regionId': '04',
  'communicationState': 'NO_ACTIVE_MESSAGE_IN_WINDOW',
  'measurementState': 'NOT_CONFIGURED',
  'messages': [],
  'measurements': [],
  'sourceHealth': [
    {
      'id': 'PAA',
      'state': 'HEALTHY',
      'lastSuccess': now.toIso8601String(),
      'maxAgeSeconds': 900,
    },
  ],
  'measuredValuesAffectHazard': false,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 21, 12);
  test('PAA no-message differs from unavailable and never confirms safety', () {
    final data = RadiationData.parse(radiation(now));
    expect(data.communicationText(now, true), contains('w pobranym zakresie'));
    expect(data.communicationText(now, false), contains('STALE'));
    expect(
      data.communicationText(now.add(const Duration(minutes: 15)), true),
      contains('STALE'),
    );
    expect(data.measurementText(now, true), contains('niezweryfikowany'));
    final warning = RadiationData.parse({
      ...radiation(now),
      'communicationState': 'ACTIVE',
    });
    expect(warning.communicationText(now, true), contains('Aktywny komunikat'));
    expect(warning.communicationText(now, false), contains('STALE'));
  });
  test('Measurements validate units/value/geometry and offline freshness', () {
    final p = {
      'stationId': 'TEST',
      'name': 'Test',
      'latitude': 53.12,
      'longitude': 18.01,
      'measuredAt': now.toIso8601String(),
      'sourceUpdatedAt': now.toIso8601String(),
      'value': 100.0,
      'unit': 'nSv/h',
      'freshness': 'FRESH',
    };
    Map<String, dynamic> payload(Map<String, dynamic> point) => {
      ...radiation(now),
      'measurementState': 'FRESH',
      'measurements': [point],
      'sourceHealth': [
        {
          'id': 'PAA_MEASUREMENTS',
          'state': 'HEALTHY',
          'lastSuccess': now.toIso8601String(),
          'maxAgeSeconds': 900,
        },
      ],
    };
    final data = RadiationData.parse(payload(p));
    expect(data.measurementText(now, true), 'Dane pomiarowe aktualne');
    expect(data.measurementText(now, false), contains('STALE'));
    expect(
      data.measurementText(now.add(const Duration(hours: 1)), true),
      contains('STALE'),
    );
    for (final bad in [
      {'unit': null},
      {'value': -1},
      {'value': double.nan},
      {'latitude': 90},
      {'longitude': 2.35},
    ]) {
      expect(
        () => RadiationData.parse(payload({...p, ...bad})),
        throwsFormatException,
      );
    }
  });
  test(
    'Snapshot cache preserves PAA after HTTP error and repository restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final status = {
        'hazardLevel': 'UNKNOWN',
        'displayText': 'Brak danych',
        'validUntil': now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      final payload = {
        'schemaVersion': 1,
        'regionId': '04',
        'serverTime': now.toIso8601String(),
        'sources': [],
        'events': [],
        'status': status,
        'nationalStatus': status,
        'radiation': radiation(now),
      };
      var fail = false;
      final repo = DataRepository(
        prefs,
        buildApi: 'https://example.org',
        client: MockClient(
          (_) async => fail
              ? http.Response('', 503)
              : http.Response(jsonEncode(payload), 200),
        ),
      );
      await repo.refresh('04');
      fail = true;
      await expectLater(repo.refresh('04'), throwsA(isA<ApiFailure>()));
      final restarted = DataRepository(prefs, buildApi: 'https://example.org');
      final cached = restarted.cached('04')!;
      expect(
        RadiationData.parse(cached.data['radiation'])
            .communicationText(now, false),
        contains('STALE'),
      );
      expect(restarted.cached('02'), isNull);
    },
  );
}
