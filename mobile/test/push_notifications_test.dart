import 'dart:async';
import 'dart:convert';

import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/push_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePushSecretStore implements PushSecretStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FakePushAdapter implements PushPlatformAdapter {
  final controller = StreamController<String>.broadcast();
  PushPermissionState current = PushPermissionState.notDetermined;
  PushPermissionState requested = PushPermissionState.authorized;
  String currentToken = 'fcm_token_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  int requestCount = 0;

  @override
  String get platform => 'ANDROID';

  @override
  bool get supported => true;

  @override
  Future<PushPermissionState> permissionState() async => current;

  @override
  Future<PushPermissionState> requestPermission() async {
    requestCount++;
    current = requested;
    return current;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenChanges => controller.stream;

  Future<void> close() => controller.close();
}

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'initialization checks state without requesting system permission',
    () async {
      final adapter = FakePushAdapter();
      final repository = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example',
        client: MockClient(
          (_) async => throw StateError('network not expected'),
        ),
      );
      final manager = PushManager(
        repository,
        adapter,
        secretStore: FakePushSecretStore(),
      );
      await manager.initializeWithoutPrompt();
      expect(adapter.requestCount, 0);
      expect(manager.state.permission, PushPermissionState.notDetermined);
      expect(manager.preferences.ukraine, false);
      expect(manager.preferences.watchedLocations, false);
      await adapter.close();
      manager.dispose();
    },
  );

  testWidgets('permission request happens only after contextual explanation', (
    tester,
  ) async {
    final adapter = FakePushAdapter();
    final repository = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://api.example',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/push/devices');
        expect(request.url.query, isEmpty);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['token'], adapter.currentToken);
        expect(body['preferences']['ukraine'], false);
        return jsonResponse({
          'registered': true,
          'deviceId': body['installationId'],
          'platform': 'ANDROID',
          'providerReady': true,
          'lastSeenAt': '2026-09-22T12:00:00Z',
        });
      }),
    );
    final manager = PushManager(
      repository,
      adapter,
      secretStore: FakePushSecretStore(),
    );
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(manager: manager)),
    );
    await tester.pumpAndSettle();

    expect(adapter.requestCount, 0);
    expect(find.text('Zgoda systemowa: jeszcze nie pytano'), findsOneWidget);

    await tester.tap(find.text('Włącz powiadomienia'));
    await tester.pumpAndSettle();
    expect(adapter.requestCount, 0);
    expect(find.text('Włączyć powiadomienia?'), findsOneWidget);
    expect(find.textContaining('bez historii GPS'), findsOneWidget);

    await tester.tap(find.text('Kontynuuj'));
    await tester.pumpAndSettle();
    expect(adapter.requestCount, 1);
    expect(find.text('Powiadomienia gotowe'), findsOneWidget);
    expect(
      find.textContaining(
        'Systemowa zgoda, rejestracja urządzenia i usługa wysyłki są gotowe',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await adapter.close();
    manager.dispose();
  });

  test(
    'token refresh updates registration without putting token in URL',
    () async {
      final requests = <http.Request>[];
      final bodies = <Map<String, dynamic>>[];
      final adapter = FakePushAdapter();
      final repository = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example',
        client: MockClient((request) async {
          requests.add(request);
          bodies.add(
            request.body.isEmpty
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
          return jsonResponse({
            'registered': true,
            'deviceId':
                bodies.last['installationId'] ??
                request.url.pathSegments.elementAt(3),
            'platform': 'ANDROID',
            'providerReady': true,
            'lastSeenAt': '2026-09-22T12:00:00Z',
          });
        }),
      );
      final manager = PushManager(
        repository,
        adapter,
        secretStore: FakePushSecretStore(),
      );
      await manager.initializeWithoutPrompt();
      await manager.enable();

      final rotated = 'fcm_token_ROTATED_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      adapter.currentToken = rotated;
      adapter.controller.add(rotated);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(requests.length, 2);
      expect(requests[0].method, 'POST');
      expect(requests[1].method, 'PUT');
      expect(requests[1].url.path, startsWith('/v1/push/devices/'));
      expect(requests[1].url.toString().contains(rotated), false);
      expect(bodies[1]['token'], rotated);

      await adapter.close();
      manager.dispose();
    },
  );

  test(
    'current watched locations are synced as preferences without history',
    () async {
      final requestBodies = <Map<String, dynamic>>[];
      final adapter = FakePushAdapter();
      final repository = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example',
        client: MockClient((request) async {
          final body = request.body.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          requestBodies.add(body);
          if (request.method == 'POST') {
            return jsonResponse({
              'registered': true,
              'deviceId': body['installationId'],
              'platform': 'ANDROID',
              'providerReady': true,
              'lastSeenAt': '2026-09-22T12:00:00Z',
            });
          }
          return jsonResponse({'ok': true, 'preferences': body});
        }),
      );
      await repository.addWatchedLocation(
        label: 'Dom',
        latitude: 53.12,
        longitude: 18.01,
        radiusKm: 10,
        regionId: '04',
      );
      final manager = PushManager(
        repository,
        adapter,
        secretStore: FakePushSecretStore(),
      );
      await manager.enable();
      await manager.setPreferences(
        const PushPreferences(
          criticalPoland: true,
          regionAlerts: true,
          watchedLocations: true,
          cyber: true,
          border: true,
          ukraine: true,
        ),
      );

      final preferencesBody = requestBodies.last;
      expect(preferencesBody['locations'], hasLength(1));
      expect(preferencesBody['locations'][0]['label'], 'Dom');
      expect(preferencesBody.containsKey('history'), false);
      expect(preferencesBody['ukraine'], true);

      final restarted = PushManager(
        repository,
        adapter,
        secretStore: FakePushSecretStore(),
      );
      expect(restarted.preferences.ukraine, true);
      expect(restarted.preferences.watchedLocations, true);
      restarted.dispose();
      await adapter.close();
      manager.dispose();
    },
  );

  test(
    'backend failure is explicit and does not fake a registration',
    () async {
      final adapter = FakePushAdapter();
      final repository = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example',
        client: MockClient((_) async => jsonResponse({'error': 'DOWN'}, 503)),
      );
      final manager = PushManager(
        repository,
        adapter,
        secretStore: FakePushSecretStore(),
      );
      await expectLater(manager.enable(), throwsA(isA<ApiFailure>()));
      expect(manager.state.registered, false);
      expect(manager.state.backendReachable, false);
      expect(manager.state.tokenAvailable, true);
      await adapter.close();
      manager.dispose();
    },
  );

  testWidgets('unconfigured preview reports backend and provider honestly', (
    tester,
  ) async {
    final repository = DataRepository(await SharedPreferences.getInstance());
    final manager = PushManager(
      repository,
      null,
      secretStore: FakePushSecretStore(),
    );
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(manager: manager)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Powiadomienia niedostępne w tej wersji'), findsOneWidget);
    expect(find.text('Wysyłka jest wyłączona'), findsOneWidget);
    expect(
      find.textContaining('nie ma kompletnej konfiguracji usługi powiadomień'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
  });
}
