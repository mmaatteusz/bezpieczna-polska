import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('service incident section and alpha.10 filters are visible', (
    tester,
  ) async {
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

    for (
      var i = 0;
      i < 12 && find.text('Zdarzenia służb').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.text('Zdarzenia służb'), findsOneWidget);
    expect(
      find.textContaining('nie podnosi automatycznie statusu'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.campaign_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Centrum alertów'), findsOneWidget);
    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, 2000),
      1000,
    );
    await tester.pumpAndSettle();
    final dropdowns = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField<String>,
    );
    expect(dropdowns, findsNWidgets(2));
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    expect(find.text('Wybuch'), findsOneWidget);
    expect(find.text('Ratownictwo'), findsOneWidget);
    expect(find.text('Zagrożenie chemiczne'), findsOneWidget);
    expect(find.text('Bezpieczeństwo publiczne'), findsOneWidget);
  });
}
