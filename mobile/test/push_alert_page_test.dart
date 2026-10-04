import 'dart:async';
import 'dart:convert';

import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/push_alert_page.dart';
import 'package:bezpieczna_polska/push_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixture(String id, {String lifecycle = 'ACTIVE'}) => {
  'id': id,
  'title': 'Komunikat $id',
  'description': 'Treść $id',
  'lifecycle': lifecycle,
  'messageContext': 'ACTUAL',
  'verification': 'CONFIRMED',
  'revision': 2,
  'regions': ['04'],
  'instructions': <String>[],
  'sources': [
    {
      'id': 'RCB',
      'name': 'RCB',
      'url': 'https://www.gov.pl/web/rcb/',
      'tier': 1,
    },
  ],
  'retrievedAt': DateTime.now().toUtc().toIso8601String(),
};

class OpenAdapter implements PushPlatformAdapter, PushOpenAdapter {
  final opens = StreamController<String>.broadcast();
  String? initial = 'alert-a';
  @override
  String get platform => 'ANDROID';
  @override
  bool get supported => false;
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<String> get openedEvents => opens.stream;
  @override
  Future<String?> initialEvent() async => initial;
  @override
  Future<String?> token() async => null;
  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.denied;
  @override
  Future<PushPermissionState> requestPermission() => permissionState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'offline tap preserves identity and retry resolves latest ended event',
    (tester) async {
      bool connected = false;
      final paths = <String>[];
      final repository = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example',
        client: MockClient((req) async {
          paths.add(req.url.path);
          if (!connected) throw http.ClientException('offline');
          if (req.url.path.endsWith('/timeline'))
            return http.Response('[]', 200);
          return http.Response(
            jsonEncode(fixture('alert-a', lifecycle: 'ENDED')),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PushAlertPage(
            eventId: 'alert-a',
            repository: repository,
            openLink: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Brak połączenia'), findsOneWidget);
      expect(find.text('Komunikat alert-a'), findsNothing);
      connected = true;
      await tester.tap(find.text('Ponów'));
      await tester.pumpAndSettle();
      expect(find.text('Komunikat alert-a'), findsOneWidget);
      expect(find.text('ZAKOŃCZONE'), findsOneWidget);
      expect(
        paths.where((p) => !p.endsWith('/timeline')),
        everyElement('/v1/events/alert-a'),
      );
      expect(repository.cachedPushEvent('alert-a')?.data['lifecycle'], 'ENDED');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cold start and background taps open the selected alert', (
    tester,
  ) async {
    final adapter = OpenAdapter();
    final repository = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://api.example',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/timeline')) return http.Response('[]', 200);
        if (req.url.path.startsWith('/v1/events/'))
          return http.Response(
            jsonEncode(fixture(req.url.path.split('/').last)),
            200,
          );
        return http.Response('{}', 503);
      }),
    );
    final manager = PushManager(repository, adapter);
    await tester.pumpWidget(
      SafetyApp(repository: repository, pushManager: manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('Komunikat alert-a'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    adapter.opens.add('alert-b');
    await tester.pumpAndSettle();
    expect(find.text('Komunikat alert-b'), findsOneWidget);
    expect(find.text('Komunikat alert-a'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
    await adapter.opens.close();
  });
}
