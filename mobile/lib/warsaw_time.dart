/// Warsaw civil time represented as UTC fields, independent of the device zone.
DateTime warsawWallClock(DateTime instant) {
  final utc = instant.toUtc();
  DateTime transition(int month) {
    final last = DateTime.utc(utc.year, month + 1, 0, 1);
    return last.subtract(Duration(days: last.weekday % 7));
  }

  final summer = !utc.isBefore(transition(3)) && utc.isBefore(transition(10));
  return utc.add(Duration(hours: summer ? 2 : 1));
}

DateTime parseWarsawWarningTime(String text) {
  if (!RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$').hasMatch(text)) {
    throw const FormatException('Nieprawidłowy czas komunikatu');
  }
  final wall = DateTime.parse('${text}Z');
  if (wall.toIso8601String().substring(0, 19) != text.replaceFirst(' ', 'T')) {
    throw const FormatException('Nieprawidłowa data komunikatu');
  }
  final candidates = [
    for (final hours in [1, 2]) wall.subtract(Duration(hours: hours)),
  ].where((utc) => warsawWallClock(utc) == wall);
  if (candidates.length != 1) {
    throw const FormatException('Niejednoznaczny czas');
  }
  return candidates.single;
}
