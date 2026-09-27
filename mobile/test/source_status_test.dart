import 'package:bezpieczna_polska/source_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> source(
  String id, {
  required String state,
  required bool enabled,
  required bool complete,
  String? coverage,
  String sourceClass = 'STATUS',
  String absenceSemantics = 'NOT_PROVABLE',
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
    'sourceClass': sourceClass,
    'absenceSemantics': absenceSemantics,
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
          sourceClass: 'STATUS',
          absenceSemantics: 'AUTHORITATIVE_EMPTY_SET',
        ),
        source(
          'STALE',
          state: 'STALE',
          enabled: true,
          complete: false,
          coverage: 'RECENT_PUBLICATIONS',
        ),
        source('DEGRADED', state: 'DEGRADED', enabled: true, complete: false),
        source('OFF', state: 'NOT_CONFIGURED', enabled: false, complete: false),
        source('BROKEN', state: 'BROKEN', enabled: true, complete: false),
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
        find.textContaining(
          'Pusty wynik może potwierdzić brak aktywnych ostrzeżeń',
        ),
        findsNothing,
      );

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

      await tester.tap(find.text('FULL'));
      await tester.pumpAndSettle();
      expect(find.text('Źródło statusu'), findsOneWidget);
      expect(
        find.textContaining(
          'Pusty wynik może potwierdzić brak aktywnych ostrzeżeń',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('FULL'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 6 && find.text('BROKEN').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pumpAndSettle();
      }

      expect(
        find.textContaining('NIEAKTUALNE • ostatnia kopia'),
        findsOneWidget,
      );
      expect(
        find.textContaining('OGRANICZONE • działa częściowo'),
        findsOneWidget,
      );
      expect(find.textContaining('NIEPODŁĄCZONE'), findsOneWidget);
      expect(find.textContaining('NIEDOSTĘPNE • błąd'), findsOneWidget);
    },
  );

  testWidgets(
    'shelter source shows declared catalog separately from stale loaded copy',
    (tester) async {
      final shelter =
          source(
            'SHELTERS',
            state: 'STALE',
            enabled: true,
            complete: true,
            coverage: 'FACILITY_CATALOG',
            sourceClass: 'REFERENCE',
          )..addAll({
            'catalogItemCount': 85877,
            'catalogDataDate': '2026-09-21',
            'itemCount': 81967,
            'dataDate': '2026-03-10',
            'catalogMismatch': true,
            'fallback': {
              'selected': 'TERTIARY_OFFICIAL_ARCHIVE',
              'reason': 'Katalog deklaruje nowsze dane; załadowano oficjalne archiwum.',
            },
          });

      await tester.pumpWidget(
        MaterialApp(
          home: SourceStatusPage(sources: [shelter], openLink: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SHELTERS'));
      await tester.pumpAndSettle();

      expect(find.text('85877 • 2026-09-21'), findsOneWidget);
      expect(find.text('81967 • 2026-03-10'), findsOneWidget);
      expect(find.text('Archiwum dane.gov.pl'), findsOneWidget);
      expect(
        find.textContaining('Katalog PSP deklaruje nowszą lub inną wersję'),
        findsOneWidget,
      );
    },
  );
}
