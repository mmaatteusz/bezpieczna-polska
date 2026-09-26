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
  List<String> regions = const ['04'],
  String sourceId = 'RSO',
  String sourceName = 'Regionalny System Ostrzegania',
}) => SafetyEvent({
  'id': id,
  'title': title,
  'description': description,
  'revision': 1,
  'regions': regions,
  'sources': [
    {
      'id': sourceId,
      'name': sourceName,
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
  test('Alerts assigns single-region warnings to their voivodeship', () {
    expect(alertRegionBucketForDisplay(const ['04']), '04');
    expect(alertRegionBucketForDisplay(const ['14']), '14');
    expect(
      alertRegionCodesForDisplay(const ['14', '04', '14', 'UNKNOWN']),
      const ['04', '14'],
    );
  });

  test('Alerts keeps multi-region warnings in one shared bucket', () {
    final first = alertRegionBucketForDisplay(const ['04', '14']);
    final second = alertRegionBucketForDisplay(const ['14', '04', '30']);

    expect(first, second);
    expect(first, isNot('04'));
    expect(first, isNot('14'));
    expect(first, isNot('PL'));
  });

  testWidgets(
    'Alerts renders voivodeship sections without duplicating multi-region cards',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final events = [
        warning(
          id: 'kp',
          title: 'Alert kujawsko-pomorski',
          validTo: '2099-01-01T00:00:00Z',
          regions: const ['04'],
        ),
        warning(
          id: 'maz',
          title: 'Alert mazowiecki',
          validTo: '2099-01-01T00:00:00Z',
          regions: const ['14'],
        ),
        warning(
          id: 'multi',
          title: 'Alert wieloregionalny',
          validTo: '2099-01-01T00:00:00Z',
          regions: const ['04', '14', '30'],
        ),
      ];

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
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('alert-region-04')), findsOneWidget);
      expect(find.byKey(const ValueKey('alert-region-14')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('alert-region-__MULTI_REGION__')),
        findsOneWidget,
      );
      expect(find.text('Alert kujawsko-pomorski'), findsOneWidget);
      expect(find.text('Alert mazowiecki'), findsOneWidget);
      expect(find.text('Alert wieloregionalny'), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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

  test('Start groups overlapping IMGW hydro warnings with the same hazard', () {
    final result = groupSafetyEventsForDashboard([
      warning(
        id: 'hydro-1',
        title: 'IMGW: Susza hydrologiczna',
        description: 'Niskie przepływy na odcinku Wisły.',
        validTo: '99999-12-31T23:59:59Z',
        regions: const ['04'],
        sourceId: 'IMGW_HYDRO',
        sourceName: 'IMGW-PIB — ostrzeżenia hydrologiczne',
      ),
      warning(
        id: 'hydro-2',
        title: 'IMGW: Susza hydrologiczna',
        description: 'Niskie przepływy w zlewni Wisły.',
        validTo: '99999-12-31T23:59:59Z',
        regions: const ['04', '14'],
        sourceId: 'IMGW_HYDRO',
        sourceName: 'IMGW-PIB — ostrzeżenia hydrologiczne',
      ),
      warning(
        id: 'hydro-3',
        title: 'IMGW: Susza hydrologiczna',
        description: 'Niskie przepływy w zlewni Wełny.',
        validTo: '99999-12-31T23:59:59Z',
        regions: const ['04', '30'],
        sourceId: 'IMGW_HYDRO',
        sourceName: 'IMGW-PIB — ostrzeżenia hydrologiczne',
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.count, 3);
    expect(result.single.areas, ['04', '14', '30']);
    expect(result.single.primary.id, 'hydro-1');
  });

  test('Start does not group same IMGW title for disjoint regions', () {
    final result = groupSafetyEventsForDashboard([
      warning(
        id: 'hydro-1',
        title: 'IMGW: Susza hydrologiczna',
        validTo: '99999-12-31T23:59:59Z',
        regions: const ['04'],
        sourceId: 'IMGW_HYDRO',
        sourceName: 'IMGW-PIB — ostrzeżenia hydrologiczne',
      ),
      warning(
        id: 'hydro-2',
        title: 'IMGW: Susza hydrologiczna',
        description: 'Inna zlewnia.',
        validTo: '99999-12-31T23:59:59Z',
        regions: const ['18'],
        sourceId: 'IMGW_HYDRO',
        sourceName: 'IMGW-PIB — ostrzeżenia hydrologiczne',
      ),
    ]);

    expect(result, hasLength(2));
  });

  test(
    'Start keeps non-IMGW warnings separate unless they are exact duplicates',
    () {
      final result = groupSafetyEventsForDashboard([
        warning(
          id: 'rso-1',
          title: 'Ostrzeżenie',
          description: 'Pierwszy komunikat.',
        ),
        warning(
          id: 'rso-2',
          title: 'Ostrzeżenie',
          description: 'Drugi komunikat.',
        ),
      ]);

      expect(result, hasLength(2));
    },
  );

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
    final event = warning(
      id: 'malformed-card',
      validTo: '2099-01-01T00:00:00Z',
    );
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
