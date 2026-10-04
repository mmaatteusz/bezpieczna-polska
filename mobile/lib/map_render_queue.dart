/// Serializes native map mutations and drops obsolete viewport work.
class MapRenderQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> run({
    required bool Function() isCurrent,
    required Future<void> Function(bool Function() isCurrent) render,
  }) {
    final next = _tail.then((_) async {
      if (isCurrent()) await render(isCurrent);
    });
    // A failed native operation must not poison subsequent viewport renders.
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return next;
  }
}
