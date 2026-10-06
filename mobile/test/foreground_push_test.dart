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
          data: {
            'eventId': 'fixture-alert',
            'kind': 'ALERT',
            'category': 'PUBLIC_SAFETY',
            'channelId': 'bp_alerts_critical',
            'notificationTag': 'PUBLIC_SAFETY:fixture-alert',
          },
          notification: RemoteNotification(title: 'Test', body: 'Odebrano'),
        ),
      );
      expect(calls.single.method, 'showForegroundNotification');
      expect(calls.single.arguments, {
        'messageId': 'received-fcm-message',
        'title': 'Test',
        'body': 'Odebrano',
        'eventId': 'fixture-alert',
        'kind': 'ALERT',
        'category': 'PUBLIC_SAFETY',
        'notificationTag': 'PUBLIC_SAFETY:fixture-alert',
        'channelId': 'bp_alerts_critical',
      });
    },
  );

  test(
    'alert updates preserve the native replacement tag and latest tap data',
    () async {
      for (final kind in ['NEW', 'ESCALATED', 'ENDED']) {
        await AndroidForegroundPush.show(
          RemoteMessage(
            messageId: 'message-$kind',
            data: {
              'eventId': 'fixture-alert',
              'kind': kind,
              'category': 'REGION_ALERTS',
              'notificationTag': 'bp-alert:fixture-alert',
            },
            notification: RemoteNotification(title: kind, body: 'Aktualizacja'),
          ),
        );
      }
      expect(calls, hasLength(3));
      expect(calls.map((call) => call.arguments['notificationTag']).toSet(), {
        'bp-alert:fixture-alert',
      });
      expect(calls.last.arguments['kind'], 'ENDED');
      expect(calls.last.arguments['eventId'], 'fixture-alert');
    },
  );

  test('data-only messages do not fabricate a visible notification', () async {
    await AndroidForegroundPush.show(
      const RemoteMessage(data: {'kind': 'TEST'}),
    );
    expect(calls, isEmpty);
  });
}
