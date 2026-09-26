import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('service incident uses Alerts filters', (tester) async {
    final now = DateTime.now().toUtc();
    final status = {
      'hazardLevel': 'UNKNOWN',
      'displayText': 'Brak wystarczających aktualnych danych',
      'validUntil': now.add(const Duration(minutes: 5)).toIso8601String(),
    };
    final event = {
      'id': 'PSP_INCIDENTS-fixture',
      'title': 'Duży pożar magazynu',
      'description': 'Ewakuowano pracowników. Działa wiele zastępów PSP.',
      'eventType': 'FIRE',
      'severity': 'HIGH',
      'verification': 'CONFIRMED',
      'lifecycle': 'UNKNOWN',
      'messageContext': 'ACTUAL',
      'regions': ['04'],
      'geographicScope': 'REGIONAL',
      'publishedAt': null,
      'publicationDate': '2026-09-21',
      'retrievedAt': now.toIso8601String(),
      'validFrom': null,
      'validTo': null,
      'sources': [
        {
          'id': 'PSP_INCIDENTS',
          'name': 'Państwowa Straż Pożarna — zdarzenia',
          'url': 'https://www.gov.pl/web/kgpsp/aktualnosci',
          'tier': 1,
        },
      ],
      'instructions': <String>[],
      'officialWarning': false,
      'reviewed': false,
      'revision': 1,
      'correction': null,
      'latitude': null,
      'longitude': null,
      'geometry': null,
      'locationText': 'Bydgoszcz',
      'areaPrecision': 'EXACT',
      'isDemo': false,
    };
    final snapshot = {
      'schemaVersion': 1,
      'regionId': '04',
      'serverTime': now.toIso8601String(),
      'status': status,
      'nationalStatus': status,
      'events': [event],
      'incidents': <dynamic>[],
      'sources': [
        {
          'id': 'PSP_INCIDENTS',
          'name': 'PSP — istotne zdarzenia',
          'url': 'https://www.gov.pl/web/kgpsp/aktualnosci',
          'state': 'HEALTHY',
          'healthStatus': 'HEALTHY',
          'lastSuccess': now.toIso8601String(),
          'maxAgeSeconds': 3600,
        },
      ],
    };
    SharedPreferences.setMockInitialValues({
      'snapshot::04': jsonEncode(snapshot),
      'region': '04',
    });
    final repo = DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(SafetyApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Duży pożar magazynu'), findsNothing);
    await tester.tap(find.text('Alerty').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtry i wyszukiwanie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wszystkie').first);
    await tester.pumpAndSettle();
    final alertsScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Duży pożar magazynu'),
      250,
      scrollable: alertsScroll,
    );
    expect(find.text('Duży pożar magazynu'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Filtry i wyszukiwanie'),
      -250,
      scrollable: alertsScroll,
    );
    await tester.tap(find.text('Bezpieczeństwo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Duży pożar magazynu'),
      250,
      scrollable: alertsScroll,
    );
    expect(find.text('Duży pożar magazynu'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Filtry i wyszukiwanie'),
      -250,
      scrollable: alertsScroll,
    );
    expect(find.text('Pogoda'), findsOneWidget);
    expect(find.text('Cyber'), findsOneWidget);
    expect(find.text('Granica'), findsOneWidget);
  });
}
