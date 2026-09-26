import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/security_levels.dart';

import 'model_test.dart' show data, response;

Map<String, dynamic> levelsData() {
  final report =
      jsonDecode(File('test/fixtures/security-levels.json').readAsStringSync())
          as Map;
  final status = report['status'] as Map;
  return {
    ...data(),
    'serverTime': '2026-09-20T12:00:00Z',
    'securityLevels': status['region']['securityLevels'],
    'nationalSecurityLevels': status['poland']['securityLevels'],
    'securityLevelsStatus': 'AVAILABLE',
    'securityLevelsLastSuccess': '2026-09-20T12:00:00Z',
    'sources': [
      {...report['health'] as Map, 'lastSuccess': '2026-09-20T12:00:00Z'},
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('real levels model, BRAVO plus CRP, expiry, offline and TTL', () {
    final d = levelsData(), now = DateTime.parse('2026-09-20T12:30:00Z');
    final s = Snapshot.parse(jsonEncode(d));
    expect(
      (s.data['securityLevels'] as List)
          .map(SecurityLevel.parse)
          .map((s) => s.label),
      containsAll(['BRAVO', 'BRAVO-CRP', 'CHARLIE']),
    );
    expect(levelsFresh(d, true, now), isTrue);
    expect(levelsFresh(d, false, now), isFalse);
    expect(levelsFresh(d, true, now.add(const Duration(hours: 3))), isFalse);
    expect(
      SecurityLevel.parse(
        (d['securityLevels'] as List).first,
      ).validAt(DateTime.parse('2026-12-01')),
      isFalse,
    );
  });
  test(
    'cache persists, malformed source does not overwrite, region/server isolation',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var fail = false;
      final r = DataRepository(
        prefs,
        buildApi: 'https://api.example',
        client: MockClient(
          (_) async => fail ? http.Response('{}', 200) : response(levelsData()),
        ),
      );
      await r.refresh('04');
      expect(r.cached('04')!.data['securityLevels'], hasLength(3));
      fail = true;
      await expectLater(r.refresh('04'), throwsA(anything));
      expect(r.cached('04')!.data['securityLevels'], hasLength(3));
      expect(r.cached('14'), isNull);
      await r.setDeveloperApi('https://other.example');
      expect(r.cached('04'), isNull);
      await r.clearData();
      expect(prefs.getKeys().where((k) => k.startsWith('snapshot:')), isEmpty);
    },
  );
  testWidgets(
    'dashboard summary separates nationwide levels from scoped infrastructure',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityLevelsSummaryCard(
              snapshot: Snapshot.parse(jsonEncode(levelsData())),
              online: true,
              now: DateTime.parse('2026-09-20T12:30:00Z'),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('Stopnie alarmowe'), findsOneWidget);
      expect(find.textContaining('BRAVO'), findsWidgets);
      expect(find.textContaining('dodatkowe stopnie dotyczą'), findsOneWidget);
      expect(find.textContaining('Dane RCB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline section labels saved copy, source links, infrastructure and 200 percent text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SecurityLevelsPanel(
                  snapshot: Snapshot.parse(jsonEncode(levelsData())),
                  online: false,
                  openSource: (_) {},
                  now: DateTime.parse('2026-09-20T12:30:00Z'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Ostatnie zapisane dane'), findsOneWidget);
      expect(find.textContaining('niepotwierdzona'), findsOneWidget);
      expect(find.textContaining('PKP Polskie'), findsOneWidget);
      expect(find.text('Otwórz oficjalne źródło'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
}
