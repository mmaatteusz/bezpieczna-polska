import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cached CERT advisory appears in the Alerts cyber category', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final status = {
      'hazardLevel': 'UNKNOWN',
      'displayText': 'Brak wystarczających aktualnych danych',
      'validUntil': now.add(const Duration(minutes: 5)).toIso8601String(),
    };
    final event = {
      'id': 'CERT-2026-200',
      'title': 'Krytyczna podatność CVE-2026-12345 w Example Gateway',
      'description': 'CERT Polska informuje o krytycznej podatności.',
      'eventType': 'CYBER',
      'severity': 'HIGH',
      'verification': 'CONFIRMED',
      'lifecycle': 'UNKNOWN',
      'messageContext': 'ACTUAL',
      'regions': <String>[],
      'geographicScope': 'UNKNOWN',
      'publishedAt': now
          .subtract(const Duration(minutes: 10))
          .toIso8601String(),
      'retrievedAt': now.toIso8601String(),
      'validFrom': null,
      'validTo': null,
      'sources': [
        {
          'id': 'CERT',
          'name': 'CERT Polska',
          'url': 'https://moje.cert.pl/komunikaty/2026/200/example/',
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
      'isDemo': false,
    };
    final snapshot = {
      'schemaVersion': 1,
      'regionId': '04',
      'serverTime': now.toIso8601String(),
      'status': status,
      'nationalStatus': status,
      'events': [event],
      'sources': [
        {
          'id': 'CERT',
          'name': 'CERT Polska — komunikaty bezpieczeństwa',
          'url': 'https://moje.cert.pl/komunikaty/',
          'state': 'HEALTHY',
          'healthStatus': 'HEALTHY',
          'lastSuccess': now.toIso8601String(),
          'maxAgeSeconds': 3600,
        },
        {
          'id': 'CSIRT_GOV',
          'name': 'CSIRT GOV — ostrzeżenia publiczne',
          'url': 'https://www.csirt.gov.pl/cer/rss',
          'state': 'NOT_CONFIGURED',
          'healthStatus': 'NOT_CONFIGURED',
          'lastSuccess': null,
          'maxAgeSeconds': 3600,
          'integrationNote': 'Publiczna lista kanałów RSS jest pusta.',
        },
      ],
    };
    SharedPreferences.setMockInitialValues({
      'region': '04',
      'snapshot::04': jsonEncode(snapshot),
    });
    final repo = DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(SafetyApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('CVE-2026-12345'), findsNothing);
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
      find.textContaining('CVE-2026-12345'),
      250,
      scrollable: alertsScroll,
    );
    expect(find.textContaining('CVE-2026-12345'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Filtry i wyszukiwanie'),
      -250,
      scrollable: alertsScroll,
    );
    await tester.tap(find.text('Cyber'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('CVE-2026-12345'),
      250,
      scrollable: alertsScroll,
    );
    expect(find.textContaining('CVE-2026-12345'), findsOneWidget);
  });
}
