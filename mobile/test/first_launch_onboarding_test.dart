import 'package:bezpieczna_polska/ui/first_launch_onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'first launch explains permission before system request and advances in order',
    (tester) async {
      var locationRequests = 0;
      var notificationRequests = 0;
      var completed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: FirstLaunchPermissionOnboarding(
            onRequestLocation: () async {
              locationRequests++;
            },
            onRequestNotifications: () async {
              notificationRequests++;
            },
            onComplete: () async {
              completed++;
            },
          ),
        ),
      );

      expect(locationRequests, 0);
      expect(notificationRequests, 0);
      expect(
        find.text('Lokalizacja dla Twojego bezpieczeństwa'),
        findsOneWidget,
      );
      expect(find.text('Zezwól na lokalizację'), findsOneWidget);
      expect(
        find.textContaining('Nie zapisujemy historii Twojego przemieszczania'),
        findsOneWidget,
      );

      await tester.tap(find.text('Zezwól na lokalizację'));
      await tester.pumpAndSettle();

      expect(locationRequests, 1);
      expect(find.text('Nie przegap ważnego alertu'), findsOneWidget);
      expect(find.text('Włącz powiadomienia'), findsOneWidget);
      expect(notificationRequests, 0);

      await tester.tap(find.text('Włącz powiadomienia'));
      await tester.pumpAndSettle();

      expect(notificationRequests, 1);
      expect(completed, 1);
    },
  );

  testWidgets(
    'unavailable push does not pretend that permission can be granted',
    (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FirstLaunchPermissionOnboarding(
          notificationsAvailable: false,
          onRequestLocation: () async {},
          onRequestNotifications: () async {},
          onComplete: () async {},
        ),
      ),
    );

    await tester.tap(find.text('Zezwól na lokalizację'));
    await tester.pumpAndSettle();

    expect(find.text('Przejdź do aplikacji'), findsOneWidget);
    expect(
      find.textContaining('nie są dostępne w tym buildzie'),
      findsOneWidget,
    );
    },
  );
}
