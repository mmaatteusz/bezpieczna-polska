import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bezpieczna_polska/shelter_markers.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> cluster(double lon, int count, {double expansion = 12}) =>
    {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [lon, 53.12],
      },
      'properties': {
        'cluster': true,
        'point_count': count,
        'expansionZoom': expansion,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'neighbouring grid clusters retain every shelter and expansion level',
    () {
      final result = shelterDisplayFeatures([
        cluster(18, 10),
        cluster(18.001, 4, expansion: 14),
        cluster(18.25, 26),
      ], 10);
      expect(result, hasLength(2));
      final counts = result.map((f) => f['properties']['point_count'] as int);
      expect(counts.toSet(), {14, 26});
      expect(counts.reduce((a, b) => a + b), 40);
      final merged = result.firstWhere(
        (f) => f['properties']['point_count'] == 14,
      );
      expect(
        merged['geometry']['coordinates'][0],
        closeTo(18.0002857, 0.000001),
      );
      expect(merged['properties']['expansionZoom'], 14);
    },
  );

  test('dense groups remain separated after their centroids move', () {
    final input = [
      for (var i = 0; i < 120; i++) cluster(18 + i * 0.002, i + 1),
    ];
    final result = shelterDisplayFeatures(input, 10);
    expect(
      result.fold<int>(
        0,
        (sum, f) => sum + (f['properties']['point_count'] as int),
      ),
      7260,
    );
    for (var a = 0; a < result.length; a++) {
      for (var b = a + 1; b < result.length; b++) {
        final x = result[a], y = result[b];
        final distance =
            ((x['geometry']['coordinates'][0] as num) -
                    (y['geometry']['coordinates'][0] as num))
                .abs() *
            512 *
            math.pow(2, 10) /
            360;
        final gap =
            (shelterClusterDiameter(x['properties']['point_count']) +
                    shelterClusterDiameter(y['properties']['point_count'])) /
                2 +
            6;
        expect(distance, greaterThanOrEqualTo(gap - 0.000001));
      }
    }
  });

  test('individual shelters retain their exact coordinates and details', () {
    final point = {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [18.01, 53.12],
      },
      'properties': {'cluster': false, 'id': 'shelter', 'address': 'Test'},
    };
    expect(shelterDisplayFeatures([point], 15), [point]);
  });

  test(
    'count bitmap uses device density and preserves a readable centre',
    () async {
      for (final ratio in [1.0, 2.0, 2.75, 3.5]) {
        final png = await shelterClusterImage(114, ratio);
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        expect(image.width, (36 * ratio).ceil());
        expect(image.height, (36 * ratio).ceil());
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var white = 0;
        for (var y = (12 * ratio).ceil(); y < (24 * ratio).floor(); y++) {
          for (var x = (7 * ratio).ceil(); x < (29 * ratio).floor(); x++) {
            final offset = (y * image.width + x) * 4;
            if (pixels.getUint8(offset) > 220 &&
                pixels.getUint8(offset + 1) > 220 &&
                pixels.getUint8(offset + 2) > 220)
              white++;
          }
        }
        expect(
          white,
          greaterThan(15 * ratio * ratio),
          reason: 'Count must be readable at density $ratio',
        );
        image.dispose();
        codec.dispose();
      }
    },
  );
}
