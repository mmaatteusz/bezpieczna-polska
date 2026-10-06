import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

/// Presents an actual FCM notification received while Android is foregrounded
/// and forwards taps on that locally-created notification back to Dart.
class AndroidForegroundPush {
  static const channel = MethodChannel('pl.bezpiecznapolska/notifications');
  static final StreamController<Map<String, String>> _taps =
      StreamController<Map<String, String>>.broadcast();
  static bool _initialized = false;
  static Map<String, String>? _initialTap;

  static Map<String, String>? _stringMap(dynamic value) {
    if (value is! Map) return null;
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is String && entry.value != null) {
        result[entry.key as String] = entry.value.toString();
      }
    }
    return result.isEmpty ? null : result;
  }

  static Future<void> initializeTapHandling() async {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTap') {
        final tap = _stringMap(call.arguments);
        if (tap != null) _taps.add(tap);
      }
    });
    try {
      _initialTap = _stringMap(
        await channel.invokeMethod<dynamic>('getInitialNotificationTap'),
      );
    } catch (_) {
      _initialTap = null;
    }
  }

  static Stream<Map<String, String>> get taps => _taps.stream;

  static Map<String, String>? takeInitialTap() {
    final value = _initialTap;
    _initialTap = null;
    return value;
  }

  static Future<void> show(RemoteMessage message) async {
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
      'kind': message.data['kind'],
      'category': message.data['category'],
      'notificationTag': message.data['notificationTag'],
      'channelId': message.data['channelId'] ?? 'bp_alerts_warning',
    });
  }
}
