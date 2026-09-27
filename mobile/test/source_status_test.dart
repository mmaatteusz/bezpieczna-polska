import 'package:bezpieczna_polska/source_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> source(
  String id, {
  required String state,
  required bool enabled,
  required bool complete,
  String? coverage,
}) {
  return {
    'id': id,
    'name': id,
    'url': 'https://example.invalid/$id',
    'state': state,
    'healthStatus': state,
    'enabled': enabled,
    'complete': complete,
    'coverage': coverage,
    'maxAgeSeconds': 900,
    'lastSuccess': null,
    'lastAttempt': null,
    'lastItemTime': null,
  };
}

void main() {
  testWidgets(
    'source page separates technical health from coverage completeness',
    (tester) async {
      final sources = [
        source(
          'LIMITED',
          state: 'HEALTHY',
          enabled: true,
          complete: false,
          coverage: 'RECENT_PUBLICATIONS',
        ),
        source(
          'FULL',
          state: 'HEALTHY',
          enabled: true,
          complete: true,
          coverage: 'ACTIVE_WARNINGS',
        ),
        source(
          'STALE',
          state: 'STALE',
          enabled: true,
          complete: false,
          coverage: 'RECENT_PUBLICATIONS',
        ),
        source(
          'DEGRADED',
          state: 'DEGRADED',
          enabled: true,
          complete: false,
        ),
        source(
          'OFF',
          state: 'NOT_CONFIGURED',
          enabled: false,
          complete: false,
        ),
        source(
          'BROKEN',
          state: 'BROKEN',
          enabled: true,
          complete: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SourceStatusPage(sources: sources, openLink: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Działa: 3'), findsOneWidget);
      expect(find.text('Nieaktualne: 1'), findsOneWidget);
      expect(find.text('Niedostępne: 1'), findsOneWidget);
      expect(find.text('Niepodłączone: 1'), findsOneWidget);
      expect(find.textContaining('PARTIAL • niepełne'), findsNothing);

      expect(
        find.text(
          'AKTUALNE • działa\n'
          'Zakres danych: ograniczony • ostatnie publikacje\n'
          'Ostatnia poprawna synchronizacja: Nie podano',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'AKTUALNE • działa\n'
          'Zakres danych: pełny dla obsługiwanego zakresu • aktywne ostrzeżenia\n'
          'Ostatnia poprawna synchronizacja: Nie podano',
        ),
        findsOneWidget,
      );

      for (var i = 0; i < 6 && find.text('BROKEN').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('NIEAKTUALNE • ostatnia kopia'), findsOneWidget);
      expect(
        find.textContaining('OGRANICZONE • działa częściowo'),
        findsOneWidget,
      );
      expect(find.textContaining('NIEPODŁĄCZONE'), findsOneWidget);
      expect(find.textContaining('NIEDOSTĘPNE • błąd'), findsOneWidget);
    },
  );
}
