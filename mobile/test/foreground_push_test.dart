import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bezpieczna_polska/foreground_push.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidForegroundPush.channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidForegroundPush.channel, null);
  });

  test(
    'received FCM notification is presented with its original identity',
    () async {
      await AndroidForegroundPush.show(
        const RemoteMessage(
          messageId: 'received-fcm-message',
          notification: RemoteNotification(title: 'Test', body: 'Odebrano'),
        ),
      );
      expect(calls.single.method, 'showForegroundNotification');
      expect(calls.single.arguments, {
        'messageId': 'received-fcm-message',
        'title': 'Test',
        'body': 'Odebrano',
        'eventId': null,
        'channelId': null,
        'expiresAt': null,
      });
    },
  );

  test('data-only messages do not fabricate a visible notification', () async {
    await AndroidForegroundPush.show(
      const RemoteMessage(data: {'kind': 'TEST'}),
    );
    expect(calls, isEmpty);
  });
  test('expired foreground warning is not displayed', () async {
    await AndroidForegroundPush.show(
      RemoteMessage(
        notification: const RemoteNotification(title: 'Alert', body: 'Stary'),
        data: {
          'eventId': 'old',
          'expiresAt': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toUtc()
              .toIso8601String(),
        },
      ),
    );
    expect(calls, isEmpty);
  });

  test(
    'foreground notification forwards selected event and severity channel',
    () async {
      await AndroidForegroundPush.show(
        const RemoteMessage(
          notification: RemoteNotification(title: 'Alert', body: 'Nowy'),
          data: {'eventId': 'selected-alert', 'channelId': 'bp_threats'},
        ),
      );
      expect(calls.single.arguments['eventId'], 'selected-alert');
      expect(calls.single.arguments['channelId'], 'bp_threats');
    },
  );
}
