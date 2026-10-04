import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/screens/dashboard_screen.dart';

import 'start_alert_regression_test.dart' show warning;

Snapshot snapshot(DateTime now, {String state = 'HEALTHY', int age = 0}) =>
    Snapshot.parse(
      jsonEncode({
        'schemaVersion': 1,
        'regionId': '04',
        'serverTime': now.toIso8601String(),
        'status': {
          'hazardLevel': 'NO_ACTIVE_WARNINGS',
          'displayText': 'Brak ostrzeżeń',
          'validUntil': now.add(const Duration(minutes: 1)).toIso8601String(),
        },
        'nationalStatus': {
          'hazardLevel': 'NO_ACTIVE_WARNINGS',
          'displayText': 'Brak ostrzeżeń',
          'validUntil': now.add(const Duration(minutes: 1)).toIso8601String(),
        },
        'sources': [
          {
            'id': 'RSO',
            'name': 'RSO',
            'url': 'https://example.org',
            'sourceClass': 'STATUS',
            'state': state,
            'maxAgeSeconds': 60,
            'lastSuccess': now
                .subtract(Duration(seconds: age))
                .toIso8601String(),
          },
        ],
        'events': [],
      }),
    );

AroundResult around(
  DateTime now, {
  bool offline = false,
  List<SafetyEvent> events = const [],
}) => AroundResult.parse({
  'schemaVersion': 1,
  'serverTime': now.toIso8601String(),
  if (offline) 'offlineSnapshotTimestamp': now.toIso8601String(),
  'query': {
    'latitude': 53.1,
    'longitude': 18.0,
    'radiusKm': 20,
    'regionId': '04',
  },
  'nearbyEvents': [],
  'regionalEvents': events
      .map((e) => {'relevance': 'REGION_RELEVANT', 'event': e.data})
      .toList(),
  'nearestShelters': {'items': []},
  'coverage': {
    'spatial': 'PARTIAL_GEOMETRY_ONLY',
    'regional': 'EXPLICIT_NATIONAL_OR_PROVINCE_SCOPE_ONLY',
    'statement': 'Ograniczony zakres',
  },
});

void main() {
  test('successful snapshot cannot mask broken or aged warning sources', () {
    final now = DateTime.now();
    expect(dashboardSourcesFresh(snapshot(now), '04', now), isTrue);
    expect(
      dashboardSourcesFresh(snapshot(now, state: 'BROKEN'), '04', now),
      isFalse,
    );
    expect(dashboardSourcesFresh(snapshot(now, age: 61), '04', now), isFalse);
    final empty = snapshot(now)..data['sources'] = [];
    expect(dashboardSourcesFresh(empty, '04', now), isFalse);
  });
  test('offline and expired locality data cannot acquire fresh status', () {
    final now = DateTime.now();
    expect(dashboardAroundFresh(around(now), now), isTrue);
    expect(dashboardAroundFresh(around(now, offline: true), now), isFalse);
    expect(
      dashboardAroundFresh(
        around(now.subtract(const Duration(minutes: 2))),
        now,
      ),
      isFalse,
    );
  });
  testWidgets('periodic Start refresh fetches locality again', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({});
    var localRequests = 0;
    final repo = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://test.example',
      client: MockClient((request) async {
        final now = DateTime.now();
        if (request.url.path.endsWith('/v1/around')) {
          localRequests++;
          return http.Response(
            jsonEncode(around(now).data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/v1/snapshot')) {
          return http.Response(
            jsonEncode(snapshot(now).data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 503);
      }),
    );
    await repo.setPrimaryLocation(
      label: 'Bydgoszcz',
      latitude: 53.1,
      longitude: 18.0,
      regionId: '04',
    );
    await tester.pumpWidget(SafetyApp(repository: repo));
    await tester.pumpAndSettle();
    expect(localRequests, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(localRequests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'local warning overrides empty province status and caps list at three',
    (tester) async {
      tester.view.physicalSize = const Size(500, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final local = List.generate(
        4,
        (i) => warning(
          id: 'local-$i',
          title: 'Lokalny komunikat $i',
          description: 'Treść $i',
          validTo: '2099-01-01T00:00:00Z',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              snapshot: snapshot(now),
              events: [
                warning(
                  id: 'unrelated',
                  title: 'Odległy komunikat',
                  validTo: '2099-01-01T00:00:00Z',
                ),
              ],
              localityAround: around(now, events: local),
              offlinePackage: null,
              online: true,
              loading: false,
              backgroundSync: false,
              region: '04',
              localityLabel: 'Bydgoszcz',
              error: null,
              onRefresh: () async {},
              onChooseLocality: () {},
              onOpenAlerts: () {},
              onOpenSecurityLevels: () {},
              onOpenEvent: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('OSTRZEŻENIA'), findsOneWidget);
      expect(find.text('Odległy komunikat'), findsNothing);
      expect(find.textContaining('Lokalny komunikat'), findsNWidgets(3));
      expect(find.text('SPOKOJNIE'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Twoja okolica')).dy,
        lessThan(tester.getTopLeft(find.text('Polska')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
