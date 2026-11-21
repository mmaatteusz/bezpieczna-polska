import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bezpieczna_polska/map_layers.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/neptun.dart';
import 'package:bezpieczna_polska/neptun_aviation.dart';
import 'package:bezpieczna_polska/shelter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/neptun_test.dart' as neptun_fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;
  testWidgets('native shelter map pans, cluster taps and navigation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final openedLinks = <String>[];
    final key = GlobalKey();
    var dense = false;
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
        if (dense && cluster) {
          features.clear();
          for (final item in [
            [0.0, 10],
            [0.012, 4],
            [-0.07, 26],
            [0.08, 114],
          ]) {
            features.add({
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [lon + item[0], lat],
              },
              'properties': {
                'cluster': true,
                'point_count': item[1].toInt(),
                'expansionZoom': 12,
              },
            });
          }
        }
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
              'total': dense && cluster
                  ? 154
                  : cluster
                  ? 3
                  : 1,
              'returned': features.length,
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
      fail(
        'Timed out waiting for native shelter map: zoom=${state.controller?.cameraPosition?.zoom}, ready=${state.ready}, message=${state.message}',
      );
    }

    await waitFor(() => state.ready == true && state.loading == false);
    final controller = state.controller as MapLibreMapController;
    controller.onCircleTapped.add(
      (circle) => debugPrint('Native circle tap: ${circle.data}'),
    );
    controller.onSymbolTapped.add(
      (symbol) => debugPrint('Native label tap: ${symbol.data}'),
    );
    Future<void> move(LatLng target, double zoom) async {
      await controller.moveCamera(CameraUpdate.newLatLngZoom(target, zoom));
      await tester.pump(const Duration(milliseconds: 500));
      await state.refresh();
      await waitFor(
        () =>
            state.loading == false &&
            (zoom < shelterDetailZoom
                ? controller.circles.isEmpty && controller.symbols.isEmpty
                : zoom < 14
                ? controller.symbols.isNotEmpty && controller.circles.isEmpty
                : controller.circles.length == 1 && controller.symbols.isEmpty),
      );
    }

    Future<void> tapMarker({bool rim = false}) async {
      // Native GeoJSON parsing and drawing can finish after the channel reply.
      await tester.pump(const Duration(seconds: 1));
      final geometry = controller.symbols.isNotEmpty
          ? controller.symbols.first.options.geometry!
          : controller.circles.single.options.geometry!;
      final point = await controller.toScreenLocation(geometry);
      final dpr = tester.view.devicePixelRatio;
      final origin = tester.getTopLeft(find.byType(MapLibreMap));
      final hits = await controller.queryRenderedFeatures(
        math.Point<double>(point.x.toDouble(), point.y.toDouble()),
        [
          ...?controller.circleManager?.layerIds,
          ...?controller.symbolManager?.layerIds,
        ],
        null,
      );
      expect(
        hits,
        isNotEmpty,
        reason: 'Native marker must be drawn before tapping',
      );
      final target =
          origin + Offset(point.x / dpr + (rim ? 12 : 0), point.y / dpr);
      debugPrint(
        'Tap target=$target native=$point dpr=$dpr hits=${hits.length} zoom=${controller.cameraPosition?.zoom}',
      );
      // WidgetTester synthetic events have no original Android MotionEvent.
      // Ask the host driver to inject an actual OS touch on the emulator.
      final socket = await Socket.connect('127.0.0.1', 18443);
      socket.writeln(
        jsonEncode({
          'x': (target.dx * dpr).round(),
          'y': (target.dy * dpr).round(),
          'paddingTop': tester.view.padding.top,
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height,
        }),
      );
      await socket.flush();
      final reply = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first;
      socket.destroy();
      expect(jsonDecode(reply)['ok'], isTrue, reason: reply);
      await tester.pump(const Duration(seconds: 1));
    }

    for (final target in [
      const LatLng(53.12, 18.01),
      const LatLng(51.25, 22.57),
      const LatLng(51.1, 16.98),
    ]) {
      await move(target, 10);
      expect(controller.symbols.single.data!['properties']['point_count'], 3);
      expect(controller.symbols.single.options.iconImage, 'shelter-cluster-0');
      expect(
        (controller.symbols.single.options.geometry!.longitude -
                target.longitude)
            .abs(),
        lessThan(0.03),
      );
      final layers = await controller.getLayerIds();
      expect(
        layers.last,
        'user-location-point',
        reason: 'Refreshing shelters must not raise them above GPS',
      );
    }
    dense = true;
    await move(const LatLng(53.12, 18.01), 10);
    expect(controller.symbols, hasLength(3));
    expect(
      controller.symbols
          .map((s) => s.data!['properties']['point_count'])
          .toSet(),
      {14, 26, 114},
    );
    // The driver captures this dense, high-density native map before the tap.
    final location = controller.symbols.first.options.geometry!;
    await controller.setGeoJsonSource('user-location', {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [location.longitude, location.latitude],
          },
          'properties': {'kind': 'user-location'},
        },
      ],
    });
    await state.refresh();
    await waitFor(() => state.loading == false);
    Future<void> expectLocationAboveShelters() async {
      expect((await controller.getLayerIds()).last, 'user-location-point');
      final screenLocation = await controller.toScreenLocation(location);
      await tester.pump(const Duration(seconds: 1));
      expect(
        await controller.queryRenderedFeatures(
          math.Point<double>(
            screenLocation.x.toDouble(),
            screenLocation.y.toDouble(),
          ),
          ['user-location-point'],
          null,
        ),
        isNotEmpty,
        reason: 'GPS must still render over an overlapping shelter group',
      );
    }

    await expectLocationAboveShelters();
    await tapMarker();
    await move(const LatLng(53.12, 18.01), 8);
    await expectLocationAboveShelters();
    expect(controller.symbols, isEmpty);
    expect(controller.circles, isEmpty);
    await move(const LatLng(53.12, 18.01), shelterDetailZoom);
    await expectLocationAboveShelters();
    await tapMarker();
    await controller.setGeoJsonSource('user-location', {
      'type': 'FeatureCollection',
      'features': [],
    });
    dense = false;
    await move(const LatLng(51.1, 16.98), shelterDetailZoom);
    await tapMarker(); // Native tap on the combined count marker.
    await waitFor(() => (controller.cameraPosition?.zoom ?? 0) >= 12);
    await move(const LatLng(51.1, 16.98), 10);
    await tapMarker(
      rim: true,
    ); // Native tap on the marker rim outside the digits.
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
    // Verify real Android symbols and grouped selection at phone density.
    final neptunInput = neptun_fixture.fixture(DateTime.now().toUtc());
    final live = neptunInput['live'] as Map;
    final template = Map<String, dynamic>.from(live['threats'][0]);
    final titles = {
      'uav': 'BSP / dron',
      'fpv': 'FPV / dron',
      'missile': 'Rakieta',
      'recon': 'Obiekt rozpoznawczy',
      'ballistic': 'Zagrożenie balistyczne',
      'kab': 'Kierowana bomba lotnicza',
      'mig31k': 'MiG-31K',
      'unknown': 'Nieokreślone zagrożenie',
    };
    final locations = [
      [31.0, 49.0],
      [31.0, 49.0],
      [31.0, 49.0],
      [30.5, 49.3],
      [31.5, 49.3],
      [30.5, 48.7],
      [31.5, 48.7],
      [31.0, 48.7],
    ];
    final threats = <Map<String, dynamic>>[];
    final features = <Map<String, dynamic>>[];
    var index = 0;
    for (final entry in titles.entries) {
      final coordinates = locations[index++];
      final id = 'neptun-${entry.key}';
      threats.add({
        ...template,
        'id': id,
        'type': entry.key,
        'title': entry.value,
        'longitude': coordinates[0],
        'latitude': coordinates[1],
      });
      features.add({
        'type': 'Feature',
        'id': id,
        'geometry': {'type': 'Point', 'coordinates': coordinates},
        'properties': {
          'threatId': id,
          'type': entry.key,
          'live': true,
          'coarse': true,
        },
      });
    }
    live['threats'] = threats;
    live['map']['features'] = features;
    neptunInput['tracks'] = [];
    neptunInput['map']['features'] = [];
    final neptunKey = GlobalKey();
    final neptunData = NeptunData.parse(neptunInput);
    final reduceMotion = ValueNotifier(true);
    addTearDown(reduceMotion.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('NEPTUN')),
          body: SafeArea(
            child: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: reduceMotion,
                builder: (context, disabled, _) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: disabled),
                  child: NeptunMap(key: neptunKey, data: neptunData),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final dynamic neptunState = neptunKey.currentState;
    for (var i = 0; i < 150 && neptunState.ready != true; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(neptunState.ready, isTrue, reason: '${neptunState.error}');
    final neptunController = neptunState.controller as MapLibreMapController;
    await neptunController.moveCamera(
      CameraUpdate.newLatLngZoom(const LatLng(49, 31), 7),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump(const Duration(seconds: 3));
    // Country-scale zoom must retain every threat type, including nearby ones.
    await neptunController.moveCamera(
      CameraUpdate.newLatLngZoom(const LatLng(49, 31), 5),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump(const Duration(seconds: 3));
    await neptunState.refreshSymbols();
    expect(neptunController.symbols, hasLength(8));
    expect(
      neptunController.symbols
          .map((symbol) => symbol.options.iconImage)
          .toSet(),
      {for (final type in titles.keys) neptunMapIconId(type)},
    );
    await neptunController.moveCamera(
      CameraUpdate.newLatLngZoom(const LatLng(49, 31), 7),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump(const Duration(seconds: 3));
    final position = await neptunController.toScreenLocation(
      const LatLng(49, 31),
    );
    final point = math.Point<double>(
      position.x.toDouble(),
      position.y.toDouble(),
    );
    final entries = await neptunController.queryRenderedFeatures(point, [
      'neptun-live-hit-points',
    ], null);
    expect(entries, hasLength(3));
    expect(entries.map((entry) => entry['properties']['type']).toSet(), {
      'uav',
      'fpv',
      'missile',
    });
    for (var i = 0; i < 150 && neptunController.symbols.length != 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(neptunController.symbols, hasLength(8));
    expect(
      neptunController.symbols
          .map((symbol) => symbol.options.iconImage)
          .toSet(),
      {for (final type in titles.keys) neptunMapIconId(type)},
    );
    final dpr = tester.view.devicePixelRatio;
    final origin = tester.getTopLeft(find.byType(MapLibreMap));
    final target = origin + Offset(point.x / dpr, point.y / dpr);
    Future<({ui.Image image, int x, int y})> capture(
      Offset target, {
      bool tap = false,
    }) async {
      final socket = await Socket.connect('127.0.0.1', 18443);
      socket.writeln(
        jsonEncode({
          'verifySymbols': true,
          'captureOnly': !tap,
          'x': (target.dx * dpr).round(),
          'y': (target.dy * dpr).round(),
          'paddingTop': tester.view.padding.top,
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height,
        }),
      );
      await socket.flush();
      final reply = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first;
      socket.destroy();
      final response = jsonDecode(reply) as Map<String, dynamic>;
      expect(response['ok'], isTrue);
      final codec = await ui.instantiateImageCodec(
        base64Decode(response['screenshot'] as String),
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      return (
        image: image,
        x: response['screenX'] as int,
        y: response['screenY'] as int,
      );
    }

    // Sample the upper arc above a standalone marker. The test style has a
    // flat background and the camera stays still for all three captures.
    final recon = await neptunController.toScreenLocation(
      const LatLng(49.3, 30.5),
    );
    final reconTarget = origin + Offset(recon.x / dpr, recon.y / dpr);
    final before = await capture(reconTarget);
    final beforePixels = (await before.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final screenWidth = before.image.width;
    before.image.dispose();

    Future<int> changedArcPixels() async {
      final frame = await capture(reconTarget);
      final current = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      frame.image.dispose();
      var changed = 0;
      final halfWidth = (7 * dpr).round();
      for (var dy = (16 * dpr).round(); dy <= (27 * dpr).round(); dy++) {
        for (var dx = -halfWidth; dx <= halfWidth; dx++) {
          final offset = ((frame.y - dy) * screenWidth + frame.x + dx) * 4;
          if ((beforePixels.getUint8(offset) - current.getUint8(offset)).abs() >
              12) {
            changed++;
          }
        }
      }
      return changed;
    }

    reduceMotion.value = false;
    await tester.pump();
    final minimumPulsePixels = 8 * dpr * dpr;
    var pulsePixels = 0;
    for (var i = 0; i < 8 && pulsePixels < minimumPulsePixels; i++) {
      await tester.pump(const Duration(milliseconds: 280));
      pulsePixels = await changedArcPixels();
    }
    expect(
      pulsePixels,
      greaterThanOrEqualTo(minimumPulsePixels),
      reason: 'No visible ring above the live marker',
    );

    reduceMotion.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await changedArcPixels(), lessThan(minimumPulsePixels));

    final tapped = await capture(target, tap: true);
    final screenshot = tapped.image;
    final pixels = (await screenshot.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final top = tapped.y - (target.dy * dpr).round();
    // Native feature queries also find invisible symbol buckets. Assert pixels
    // from Android's actual screen, excluding each badge's white border.
    for (final location in [
      const LatLng(49, 31),
      for (final coordinate in locations.skip(3))
        LatLng(coordinate[1], coordinate[0]),
    ]) {
      final screen = await neptunController.toScreenLocation(location);
      final x = (origin.dx * dpr + screen.x).round();
      final y = (origin.dy * dpr + screen.y + top).round();
      final radius = (10 * dpr).round();
      var whitePixels = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > radius * radius) continue;
          final px = x + dx, py = y + dy;
          if (px < 0 ||
              py < 0 ||
              px >= screenshot.width ||
              py >= screenshot.height) {
            continue;
          }
          final offset = (py * screenshot.width + px) * 4;
          if (pixels[offset] > 245 &&
              pixels[offset + 1] > 245 &&
              pixels[offset + 2] > 245) {
            whitePixels++;
          }
        }
      }
      expect(
        whitePixels,
        greaterThan(5 * dpr * dpr),
        reason: 'Native threat icon is blank at $location',
      );
    }
    screenshot.dispose();
    for (
      var i = 0;
      i < 150 && find.text('3 wpisów w tym obszarze').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
    expect(find.text('3 wpisów w tym obszarze'), findsOneWidget);
    for (final title in ['BSP / dron', 'FPV / dron', 'Rakieta']) {
      expect(find.text(title), findsWidgets);
    }
    await tester.tap(find.text('Rakieta').first);
    await tester.pumpAndSettle();
    expect(find.text('Typ: Rakieta'), findsOneWidget);
    Navigator.of(neptunKey.currentContext!).pop();
    await tester.pumpAndSettle();

    final aviation = await NeptunAviationData.load();
    final lublin = (aviation.airports['features'] as List).firstWhere(
      (airport) => airport['properties']['icao'] == 'EPLB',
    );
    final airportCoordinates = (lublin['geometry']['coordinates'] as List)
        .cast<num>();
    final airportLocation = LatLng(
      airportCoordinates[1].toDouble(),
      airportCoordinates[0].toDouble(),
    );
    await neptunController.moveCamera(
      CameraUpdate.newLatLngZoom(airportLocation, 7.5),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final airportScreen = await neptunController.toScreenLocation(
      airportLocation,
    );
    final airportPoint = math.Point<double>(
      airportScreen.x.toDouble(),
      airportScreen.y.toDouble(),
    );
    expect(
      await neptunController.getLayerIds(),
      contains('neptun-country-colors'),
    );

    for (final layer in NeptunAviationLayer.values) {
      Future<List<dynamic>> hits() => neptunController.queryRenderedFeatures(
        airportPoint,
        [layer.hitLayerId],
        null,
      );
      expect(await hits(), isEmpty);
      final chip = find.widgetWithText(FilterChip, layer.label);
      expect(
        tester.widget<FilterChip>(chip).onSelected,
        isNotNull,
        reason: '${layer.label} is available',
      );
      await tester.tap(chip);
      var entries = <dynamic>[];
      for (var attempt = 0; attempt < 15 && entries.isEmpty; attempt++) {
        await tester.pump(const Duration(milliseconds: 150));
        entries = await hits();
      }
      expect(
        tester.widget<FilterChip>(chip).selected,
        isTrue,
        reason: layer.label,
      );
      expect(
        entries.map((entry) => entry['properties']['icao']),
        contains('EPLB'),
        reason: layer.label,
      );
      if (layer == NeptunAviationLayer.traffic) {
        expect(
          entries.first['properties']['operations'],
          aviation.bundledTraffic.operations['EPLB'],
        );
      }
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<FilterChip>(chip).selected,
        isFalse,
        reason: layer.label,
      );
      expect(await hits(), isEmpty);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
