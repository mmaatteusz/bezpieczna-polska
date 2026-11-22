import 'dart:async';
import 'dart:convert';

import 'package:bezpieczna_polska/map_layers.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/warsaw_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const notice = '''<newses><pagination_info totalItems="1"/><news>
<id>123</id><title>Wezbranie</title><content>Wzrost poziomu wody</content>
<created_at>2025-10-24 18:30:00</created_at><valid_from>2025-10-24 19:00:00</valid_from>
<valid_to>2090-02-01 09:00:00</valid_to><provinces><province>Kujawsko-Pomorskie</province></provinces>
</news></newses>''';
const meteo = {
  'nazwa_zdarzenia': 'Silny wiatr',
  'biuro': 'Gdynia',
  'numer': '101',
  'stopień': '2',
  'opublikowano': '2025-10-24 18:30:00',
  'obowiazuje_od': '2025-10-24 19:00:00',
  'obowiazuje_do': '2090-02-01 09:00:00',
  'tresc': 'Silne porywy',
  'teryt': ['0403'],
};
http.Response reply(String text) => http.Response.bytes(utf8.encode(text), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'on a cold start a failed national request can still yield both map layers',
    () async {
      var calls = 0;
      var rso = notice;
      var weather = jsonEncode([meteo]);
      final repo = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://example.org',
        client: MockClient((req) async {
          calls++;
          if (req.url.host == 'example.org') return http.Response('', 503);
          if (req.url.host == 'komunikaty.tvp.pl') return reply(rso);
          if (req.url.path.endsWith('warningsmeteo')) return reply(weather);
          return http.Response('', 502);
        }),
      );
      await expectLater(
        repo.refresh('PL'),
        throwsA(isA<ApiFailure>().having((f) => f.statusCode, 'HTTP', 503)),
      );
      final startup = repo.officialMapWarnings.refresh();
      final map = repo.officialMapWarnings.refresh();
      final feeds = await startup;
      expect(await map, same(feeds));
      expect(calls, 4);
      expect(repo.cached('PL'), isNull);
      expect(feeds.map((f) => f.source), ['RSO', 'IMGW_METEO']);
      final rsoEvent = feeds.first.events.single;
      expect(rsoEvent.data['messageContext'], 'UNKNOWN');
      final now = DateTime.utc(2026, 11, 22);
      expect(
        mapEventFeatures(rsoEvent, now).single['properties']['mapCategory'],
        'ALERT',
      );
      expect(
        mapEventFeatures(
          feeds.last.events.single,
          now,
          administrativeAnchors: {
            '0403': [18, 53],
          },
        ).single['properties']['terytCode'],
        '0403',
      );
      expect(mapEventFeatures(rsoEvent, DateTime.utc(2090, 2, 1, 8)), isEmpty);
      expect(
        mapEventFeatures(
          SafetyEvent({...rsoEvent.data, 'title': 'Ćwiczenia służb'}),
          now,
        ),
        isEmpty,
      );
      expect(
        mapEventFeatures(SafetyEvent({...rsoEvent.data, 'validTo': null}), now),
        isEmpty,
      );
      final restarted = DataRepository(repo.prefs, buildApi: repo.api);
      expect(
        restarted.officialMapWarnings.cached().first.events.single.id,
        'RSO-123',
      );

      rso = '<newses><pagination_info totalItems="1"/></newses>';
      weather = '{"message":"Brak ostrzeżeń meteorologicznych"}';
      final later = await repo.officialMapWarnings.refresh(force: true);
      expect(later.first.checkedAt, feeds.first.checkedAt);
      expect(later.first.events.single.id, 'RSO-123');
      expect(later.last.events, isEmpty);
    },
  );
  test(
    'clearing local data while public feeds are loading discards those results',
    () async {
      final replyLater = Completer<http.Response>();
      final repo = DataRepository(
        await SharedPreferences.getInstance(),
        client: MockClient((_) => replyLater.future),
      );
      final read = repo.officialMapWarnings.refresh();
      await repo.clearData();
      replyLater.complete(reply(notice));
      expect(await read, isEmpty);
      expect(repo.officialMapWarnings.cached(), isEmpty);
    },
  );
  test(
    'warning validity uses Warsaw time in summer and winter on any device',
    () {
      expect(
        parseWarsawWarningTime('2026-07-01 10:00:00'),
        DateTime.utc(2026, 7, 1, 8),
      );
      expect(
        parseWarsawWarningTime('2026-11-01 10:00:00'),
        DateTime.utc(2026, 11, 1, 9),
      );
      for (final text in [
        '2026-03-29 02:30:00',
        '2026-10-25 02:30:00',
        '2026-02-30 10:00:00',
      ]) {
        expect(() => parseWarsawWarningTime(text), throwsFormatException);
      }
    },
  );
}
