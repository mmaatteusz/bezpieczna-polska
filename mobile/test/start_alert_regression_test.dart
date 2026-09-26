import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/screens/alerts_screen.dart';
import 'package:bezpieczna_polska/ui/safety_event_card.dart';

SafetyEvent warning({
  required String id,
  String title = 'Silne burze',
  String description = 'Możliwe silne porywy wiatru i intensywne opady.',
  String validTo = '2026-09-26T18:00:00Z',
}) => SafetyEvent({
  'id': id,
  'title': title,
  'description': description,
  'revision': 1,
  'regions': ['04'],
  'sources': [
    {
      'id': 'RSO',
      'name': 'Regionalny System Ostrzegania',
      'url': 'https://example.org/warning',
      'tier': 1,
    },
  ],
  'lifecycle': 'ACTIVE',
  'messageContext': 'ACTUAL',
  'verification': 'CONFIRMED',
  'severity': 'HIGH',
  'officialWarning': true,
  'validFrom': '2026-09-25T12:00:00Z',
  'validTo': validTo,
  'publishedAt': '2026-09-25T11:55:00Z',
});

void main() {
  test('Start display collapses semantic duplicates with different ids', () {
    final duplicates = List.generate(
      5,
      (index) => warning(id: 'warning-$index'),
    );

    final result = deduplicateSafetyEventsForDisplay(duplicates);

    expect(result, hasLength(1));
    expect(result.single.id, 'warning-0');
  });

  test('Start display keeps genuinely different warnings', () {
    final result = deduplicateSafetyEventsForDisplay([
      warning(id: 'warning-1'),
      warning(
        id: 'warning-2',
        title: 'Silny wiatr',
        description: 'Możliwe porywy przekraczające 90 km/h.',
      ),
    ]);

    expect(result, hasLength(2));
  });

  test('far-future sentinel validity is treated as open ended', () {
    final event = warning(id: 'sentinel', validTo: '99999-12-31T23:59:59Z');

    expect(safetyEventHasOpenEndedValidity(event), isTrue);
    expect(
      safetyEventTimeLabel(event, DateTime.utc(2026, 9, 25)),
      'Obowiązuje do odwołania',
    );
  });

  testWidgets('warning card never exposes technical year 99999', (
    tester,
  ) async {
    final event = warning(
      id: 'sentinel-card',
      validTo: '99999-12-31T23:59:59Z',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyEventCard(event: event, onTap: () {}),
        ),
      ),
    );

    expect(find.text('Obowiązuje do odwołania'), findsOneWidget);
    expect(find.textContaining('99999'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed alert card falls back instead of red ErrorWidget', (
    tester,
  ) async {
    final event = warning(id: 'malformed-card', validTo: '2099-01-01T00:00:00Z');
    event.data['regions'] = null;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyEventCard(event: event, onTap: () {}),
        ),
      ),
    );

    expect(
      find.text('Nie udało się wyświetlić szczegółów komunikatu'),
      findsOneWidget,
    );
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Alerts keeps long scrolling lists stable', (tester) async {
    final events = List.generate(
      80,
      (index) => warning(
        id: 'scroll-$index',
        title: 'Alert przewijania $index',
        description: 'Treść testowa $index',
        validTo: '2099-01-01T00:00:00Z',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertsScreen(
            events: events,
            onOpenEvent: (_) {},
            onRefresh: () async {},
          ),
        ),
      ),
    );

    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Alert przewijania 79'),
      500,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alert przewijania 79'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
