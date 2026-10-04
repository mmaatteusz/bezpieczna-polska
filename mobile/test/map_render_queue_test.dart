import 'dart:async';

import 'package:bezpieczna_polska/map_render_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'distant pan supersedes a render already awaiting native clear',
    () async {
      final queue = MapRenderQueue();
      final clearing = Completer<void>();
      final started = Completer<void>();
      final markers = <String>[];
      var current = 1;
      final first = queue.run(
        isCurrent: () => current == 1,
        render: (valid) async {
          started.complete();
          await clearing.future;
          markers.clear();
          if (valid()) markers.add('Bydgoszcz');
        },
      );
      await started.future;
      current = 2;
      final second = queue.run(
        isCurrent: () => current == 2,
        render: (_) async {
          markers
            ..clear()
            ..add('Lublin');
        },
      );
      current = 3;
      final latest = queue.run(
        isCurrent: () => current == 3,
        render: (_) async {
          markers
            ..clear()
            ..add('Wroclaw');
        },
      );
      clearing.complete();
      await Future.wait([first, second, latest]);
      expect(markers, ['Wroclaw']);
    },
  );

  test('native error and disposal do not poison or revive renders', () async {
    final queue = MapRenderQueue();
    await expectLater(
      queue.run(
        isCurrent: () => true,
        render: (_) async => throw StateError('disposed native style'),
      ),
      throwsStateError,
    );
    var rendered = false;
    await queue.run(
      isCurrent: () => false,
      render: (_) async {
        rendered = true;
      },
    );
    expect(rendered, isFalse);
    await queue.run(
      isCurrent: () => true,
      render: (_) async {
        rendered = true;
      },
    );
    expect(rendered, isTrue);
  });
}
