import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/event_details.dart';

Map<String, dynamic> fixture() {
  final now = DateTime.now().toUtc();
  final reports = ['RCB', 'RSO', 'WCZK-04']
      .map(
        (source) => <String, dynamic>{
          'id': '$source-test',
          'title': 'Powódź — fixture',
          'description': 'Wyłącznie syntetyczny komunikat testowy.',
          'revision': 1,
          'regions': ['04'],
          'eventType': 'WEATHER',
          'lifecycle': 'ACTIVE',
          'messageContext': 'ACTUAL',
          'verification': 'CONFIRMED',
          'publishedAt': now.toIso8601String(),
          'retrievedAt': now.toIso8601String(),
          'validFrom': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'validTo': now.add(const Duration(hours: 1)).toIso8601String(),
          'sources': [
            {
              'id': source,
              'name': source,
              'url': 'https://www.gov.pl/',
              'tier': 1,
            },
          ],
        },
      )
      .toList();
  final status = {
    'displayText': 'Ostrzeżenie testowe',
    'hazardLevel': 'CAUTION',
    'validUntil': now.add(const Duration(minutes: 1)).toIso8601String(),
  };
  return {
    'schemaVersion': 1,
    'serverTime': now.toIso8601String(),
    'regionId': '04',
    'status': status,
    'nationalStatus': status,
    'sources': [],
    'events': reports,
    'incidents': [
      {
        'id': 'INC-012345678901234567890123',
        'revision': 2,
        'primaryEventId': reports.first['id'],
        'relatedEventIds': reports.map((e) => e['id']).toList(),
        'sourceCount': 3,
        'hasConflictingReports': true,
        'reports': reports,
      },
    ],
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('one card keeps all original reports and source filters', () {
    final s = Snapshot.parse(jsonEncode(fixture()));
    expect(s.events, hasLength(3));
    expect(s.alertEvents, hasLength(1));
    final card = s.alertEvents.single;
    expect(card.isRcb && card.isRso && card.isWczk, isTrue);
    expect(card.sources, hasLength(3));
    expect(card.reports, hasLength(3));
    expect(card.sourceSummary, 'Komunikaty z 3 źródeł');
    expect(card.revision, 2);
    expect(card.hasConflictingReports, isTrue);
  });
  test('bad incident membership fails closed, old snapshots still work', () {
    final bad = fixture();
    ((bad['incidents'] as List).first as Map)['primaryEventId'] = 'missing';
    expect(() => Snapshot.parse(jsonEncode(bad)), throwsFormatException);
    final old = fixture()..remove('incidents');
    expect(Snapshot.parse(jsonEncode(old)).alertEvents, hasLength(3));
  });
  test('incident timeline uses dedicated endpoint and keeps source revision payload', () async {
    final event = (fixture()['events'] as List).first;
    final repo = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://api.example',
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/v1/incidents/INC-012345678901234567890123/timeline',
        );
        return http.Response(
          jsonEncode([
            {
              'payload': event,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
              'reason': 'Source changed',
              'changes': [],
            },
          ]),
          200,
        );
      }),
    );
    expect(
      await repo.eventTimeline('INC-012345678901234567890123', incident: true),
      hasLength(1),
    );
  });
  testWidgets(
    'Alert Center shows one card for RCB RSO WCZK and retains details',
    (tester) async {
      final raw = fixture();
      final repo = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/timeline') ? [] : raw),
            200,
          ),
        ),
      );
      await tester.pumpWidget(SafetyApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alerty').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Komunikaty z 3 źródeł'), 200);
      expect(find.text('Komunikaty z 3 źródeł'), findsOneWidget);
      expect(find.text('Powódź — fixture'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailsPage(
            event: Snapshot.parse(jsonEncode(raw)).alertEvents.single,
            repository: repo,
            openLink: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Źródła różnią się'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
