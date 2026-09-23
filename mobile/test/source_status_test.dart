import 'package:bezpieczna_polska/source_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> source(
  String id, {
  required String state,
  required bool enabled,
  required bool complete,
}) {
  return {
    'id': id,
    'name': id,
    'url': 'https://example.invalid/$id',
    'state': state,
    'healthStatus': state,
    'enabled': enabled,
    'complete': complete,
    'maxAgeSeconds': 900,
    'lastSuccess': null,
    'lastAttempt': null,
    'lastItemTime': null,
  };
}

void main() {
  testWidgets(
    'source page distinguishes active partial, disconnected and broken sources',
    (tester) async {
      final sources = [
        source('PARTIAL', state: 'HEALTHY', enabled: true, complete: false),
        source('FULL', state: 'HEALTHY', enabled: true, complete: true),
        source('OFF', state: 'NOT_CONFIGURED', enabled: false, complete: false),
        source('BROKEN', state: 'BROKEN', enabled: true, complete: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SourceStatusPage(sources: sources, openLink: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AKTYWNE • CZĘŚCIOWE'), findsOneWidget);
      expect(find.textContaining('AKTUALNE'), findsOneWidget);
      expect(
        find.textContaining('NIEPODŁĄCZONE • ŚWIADOMIE POZA ZAKRESEM'),
        findsOneWidget,
      );
      expect(find.textContaining('BŁĄD'), findsOneWidget);
    },
  );
}
