import 'dart:convert';

import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/shelter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native shelter map pans, cluster taps and navigation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final openedLinks = <String>[];
    final key = GlobalKey();
    final repo = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://map-test.invalid',
      client: MockClient((request) async {
        final q = request.url.queryParameters;
        final bbox = q['bbox']!.split(',').map(double.parse).toList();
        final zoom = double.parse(q['zoom']!);
        final lon = (bbox[0] + bbox[2]) / 2;
        final lat = (bbox[1] + bbox[3]) / 2;
        final cluster = zoom < 14;
        final features = [
          {
            'type': 'Feature',
            'id': 'native-test',
            'geometry': {
              'type': 'Point',
              'coordinates': [lon, lat],
            },
            'properties': cluster
                ? {
                    'cluster': true,
                    'point_count': 3,
                    'expansionZoom': zoom < 9
                        ? 9
                        : zoom < 12
                        ? 12
                        : 14,
                  }
                : {
                    'id': 'native-test',
                    'cluster': false,
                    'address': 'Schron testowy',
                    'municipality': 'Test',
                    'county': 'Test',
                    'regionId': 'PL',
                    'sourceId': 'SHELTERS',
                    'sourceType': 'MDS',
                    'sourceAvailability': 'UNKNOWN',
                    'category': 'SHELTER_POINT',
                    'protectionClass': 'UNKNOWN',
                    'availability': 'UNKNOWN',
                    'latitude': lat,
                    'longitude': lon,
                    'dataDate': '2026-09-22',
                    'sourceUpdatedAt': '2026-09-22T09:00:00Z',
                  },
          },
        ];
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'metadata': {
              'schemaVersion': 1,
              'layerId': 'shelters',
              'authority': 'OFFICIAL_PL',
              'bbox': bbox,
              'zoom': zoom,
              'regionId': q['regionId'],
              'availability': q['availability'],
              'total': cluster ? 3 : 1,
              'returned': 1,
              'serverTime': DateTime.now().toIso8601String(),
            },
            'features': features,
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShelterMap(
              key: key,
              repository: repo,
              region: 'PL',
              ukraine: false,
              events: const [],
              watchedLocations: const [],
              openEvent: (_) {},
              openLink: openedLinks.add,
            ),
          ),
        ),
      ),
    );
    final dynamic state = key.currentState;
    Future<void> waitFor(bool Function() check) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (check()) return;
      }
      fail('Timed out waiting for native shelter map');
    }

    await waitFor(() => state.ready == true && state.loading == false);
    final controller = state.controller as MapLibreMapController;
    Future<void> move(LatLng target, double zoom) async {
      await controller.moveCamera(CameraUpdate.newLatLngZoom(target, zoom));
      await tester.pump(const Duration(milliseconds: 500));
      await state.refresh();
      await waitFor(
        () => state.loading == false && controller.circles.length == 1,
      );
    }

    Future<void> tapMarker({bool rim = false}) async {
      final marker = controller.circles.single;
      final point = await controller.toScreenLocation(marker.options.geometry!);
      final dpr = tester.view.devicePixelRatio;
      final origin = tester.getTopLeft(find.byType(MapLibreMap));
      await tester.tapAt(
        origin + Offset(point.x / dpr + (rim ? 16 : 0), point.y / dpr),
      );
      await tester.pump(const Duration(milliseconds: 600));
    }

    for (final target in [
      const LatLng(53.12, 18.01),
      const LatLng(51.25, 22.57),
      const LatLng(51.1, 16.98),
    ]) {
      await move(target, 10);
      expect(controller.symbols.single.options.textField, '3');
      expect(
        (controller.circles.single.options.geometry!.longitude -
                target.longitude)
            .abs(),
        lessThan(0.03),
      );
    }
    await move(const LatLng(51.1, 16.98), 8);
    await tapMarker(); // Native tap on the count label.
    await waitFor(() => (controller.cameraPosition?.zoom ?? 0) >= 9);
    await move(const LatLng(51.1, 16.98), 10);
    await tapMarker(
      rim: true,
    ); // Native tap on the green circle outside the label.
    await waitFor(() => (controller.cameraPosition?.zoom ?? 0) >= 12);
    await move(const LatLng(51.1, 16.98), 15);
    expect(controller.symbols, isEmpty);
    await tapMarker();
    await waitFor(() => find.text('Nawiguj do schronu').evaluate().isNotEmpty);
    await tester.tap(find.text('Nawiguj do schronu'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(openedLinks, hasLength(1));
    final destination = Uri.parse(
      openedLinks.single,
    ).queryParameters['destination']!;
    final coordinates = destination.split(',').map(double.parse).toList();
    expect((coordinates[0] - 51.1).abs(), lessThan(0.03));
    expect((coordinates[1] - 16.98).abs(), lessThan(0.03));
    await move(const LatLng(51.1, 16.98), 3);
    await waitFor(
      () => controller.circles.isEmpty && controller.symbols.isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
