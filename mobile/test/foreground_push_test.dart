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
      });
    },
  );

  test('data-only messages do not fabricate a visible notification', () async {
    await AndroidForegroundPush.show(
      const RemoteMessage(data: {'kind': 'TEST'}),
    );
    expect(calls, isEmpty);
  });
}
