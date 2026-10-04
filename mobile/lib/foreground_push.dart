import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

/// Presents an actual FCM notification received while Android is foregrounded.
/// Background notifications remain owned by the Firebase Android SDK.
class AndroidForegroundPush {
  static const channel = MethodChannel('pl.bezpiecznapolska/notifications');

  static Future<void> show(RemoteMessage message) async {
    final expires = DateTime.tryParse(
      message.data['expiresAt']?.toString() ?? '',
    );
    if (expires != null && !expires.isAfter(DateTime.now().toUtc())) return;
    final notification = message.notification;
    if (notification == null) return;
    final title = notification.title ?? 'Bezpieczna Polska';
    final body = notification.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    await channel.invokeMethod<void>('showForegroundNotification', {
      'messageId': message.messageId,
      'title': title,
      'body': body,
      'eventId': message.data['eventId'],
      'channelId':
          message.data['channelId'] ?? message.notification?.android?.channelId,
      'expiresAt': message.data['expiresAt'],
    });
  }
}
