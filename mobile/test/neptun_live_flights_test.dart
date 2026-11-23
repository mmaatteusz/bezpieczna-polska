import 'dart:async';
import 'dart:convert';

import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/neptun.dart';
import 'package:bezpieczna_polska/neptun_live_flights.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> flight({double latitude = 52.3, String country = 'PL'}) =>
    {
      'id': '123abcd',
      'number': 'LO321',
      'country': country,
      'latitude': latitude,
      'longitude': 21.1,
      'track': 74,
      'altitudeFt': 30000,
      'speedKt': 420,
      'observedAt': '2026-11-23T13:32:50Z',
      'from': 'WAW',
      'to': null,
    };

Map<String, Object?> live(List<Map<String, Object?>> flights) => {
  'state': 'LIVE',
  'checkedAt': '2026-11-23T13:33:00Z',
  'limitReached': false,
  'flights': flights,
};

class _FlightMap extends MapLibrePlatform {
  late OnPlatformViewCreatedCallback create;
  late Completer<void> styleReady;
  List<dynamic> aircraft = [];

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    create = onPlatformViewCreated;
    return const SizedBox.expand();
  }

  @override
  Future<List> getLayerIds() async => [];

  @override
  Future<LatLngBounds> getVisibleRegion() async => LatLngBounds(
    southwest: const LatLng(43, 14),
    northeast: const LatLng(56, 42),
  );

  @override
  Future<bool?> animateCamera(
    CameraUpdate update, {
    Duration? duration,
  }) async => true;

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) async {
    if (sourceId == neptunLiveFlightsSource) {
      aircraft = geojson['features'] as List;
    }
    if (sourceId == 'neptun-history' && !styleReady.isCompleted) {
      styleReady.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'each refresh draws the current coordinate with the reported track',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var requests = 0;
      final repository = DataRepository(
        prefs,
        buildApi: 'https://example.test',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/neptun/live-flights');
          expect(request.url.hasQuery, isFalse);
          expect(request.headers.containsKey('Authorization'), isFalse);
          requests++;
          return http.Response(
            jsonEncode(live([flight(latitude: requests == 1 ? 52.3 : 52.4)])),
            200,
          );
        }),
      );
      final first = await repository.refreshNeptunLiveFlights();
      final next = await repository.refreshNeptunLiveFlights();
      expect(next.state, NeptunLiveFlightsState.live);
      expect(next.flights.values.single.number, 'LO321');
      expect(next.flights.values.single.to, isNull);
      expect(first.flights.values.single.feature['geometry'], {
        'type': 'Point',
        'coordinates': [21.1, 52.3],
      });
      expect(next.map['features'], [
        {
          'type': 'Feature',
          'id': '123abcd',
          'geometry': {
            'type': 'Point',
            'coordinates': [21.1, 52.4],
          },
          'properties': {'flightId': '123abcd', 'track': 74},
        },
      ]);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'an old backend is distinct from a valid response with zero flights',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = DataRepository(
        prefs,
        buildApi: 'https://example.test',
        client: MockClient((_) async => http.Response('', 404)),
      );
      expect(
        (await repository.refreshNeptunLiveFlights()).state,
        NeptunLiveFlightsState.notConfigured,
      );
      expect(
        NeptunLiveFlights.parse(live([])).state,
        NeptunLiveFlightsState.live,
      );
      expect(
        () => NeptunLiveFlights.parse(live([flight(country: 'UA')])),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'the map refreshes only the selected layer and clears unavailable positions',
    (tester) async {
      final platform = _FlightMap();
      final createInstance = MapLibrePlatform.createInstance;
      MapLibrePlatform.createInstance = () => platform;
      addTearDown(() => MapLibrePlatform.createInstance = createInstance);

      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NeptunMap(
                data: null,
                fetchLiveFlights: () async {
                  requests++;
                  if (requests == 3) {
                    throw const ApiFailure(ApiFailureKind.network);
                  }
                  return NeptunLiveFlights.parse(
                    live([flight(latitude: requests == 1 ? 52.3 : 52.4)]),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        platform.styleReady = Completer<void>();
        platform.create(0);
        platform.onMapStyleLoadedPlatform(null);
        await platform.styleReady.future.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(requests, 0);

      final chip = find.widgetWithText(FilterChip, 'Loty na żywo');
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(platform.aircraft.single['geometry']['coordinates'], [21.1, 52.3]);

      await tester.pump(const Duration(minutes: 1));
      expect(requests, 2);
      expect(platform.aircraft.single['geometry']['coordinates'], [21.1, 52.4]);

      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(platform.aircraft, isEmpty);
      expect(find.text('Pozycje lotów chwilowo niedostępne.'), findsOneWidget);

      await tester.tap(chip);
      await tester.pump(const Duration(minutes: 2));
      expect(requests, 3);
      expect(platform.aircraft, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
