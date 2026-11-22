import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

const lublinPassengerBoardUrl = 'https://www.airport.lublin.pl/przyloty/';

class NeptunPassengerBoard {
  static const airport = 'EPLB';
  static const maxAge = Duration(minutes: 5);

  final DateTime checkedAt;
  final int arrivals, departures, landed, departed;

  const NeptunPassengerBoard(
    this.checkedAt,
    this.arrivals,
    this.departures, {
    required this.landed,
    required this.departed,
  });

  bool isCurrent(DateTime now) =>
      now.difference(checkedAt) < maxAge &&
      _warsawDate(now) == _warsawDate(checkedAt);

  static String _warsawDate(DateTime time) {
    final utc = time.toUtc();
    DateTime lastSunday(int month) {
      final last = DateTime.utc(utc.year, month + 1, 0, 1);
      return last.subtract(Duration(days: last.weekday % 7));
    }

    final summer = !utc.isBefore(lastSunday(3)) && utc.isBefore(lastSunday(10));
    final shifted = utc.add(Duration(hours: summer ? 2 : 1));
    return '${shifted.day.toString().padLeft(2, '0')}/${shifted.month.toString().padLeft(2, '0')}/${shifted.year}';
  }

  static NeptunPassengerBoard? fromLublinHtml(String markup, DateTime now) {
    final document = html.parse(markup);
    final date = _warsawDate(now);
    final flightCode = RegExp(r'^[A-Z0-9]{2}\s?\d{1,4}[A-Z]?$');
    ({int total, int completed})? count(String kind, RegExp completedStatus) {
      final table = document.querySelector('#$kind-table [role="table"]');
      if (table == null) return null;
      final rows = table.querySelectorAll('.flight-row-grid');
      if (rows.isEmpty) return null;
      final today = <String>{};
      final cancelled = <String>{};
      final completed = <String>{};
      for (final row in rows) {
        final cells = row.children
            .where((cell) => cell.attributes['role'] == 'cell')
            .toList();
        if (cells.length < 6 || cells[1].text.trim() != date) continue;
        final code = cells[3].text.trim().toUpperCase();
        if (!flightCode.hasMatch(code)) continue;
        today.add(code);
        final status = cells[5].text.trim().toUpperCase();
        if (status.contains('ODWOŁAN') || status.contains('CANCEL')) {
          cancelled.add(code);
        }
        if (completedStatus.hasMatch(status)) completed.add(code);
      }
      return today.isEmpty
          ? null
          : (
              total: today.difference(cancelled).length,
              completed: completed.difference(cancelled).length,
            );
    }

    final arrivals = count(
      'arrivals',
      RegExp(r'^(WYLĄDOWAŁ|PRZYLECIAŁ|LANDED|ARRIVED)'),
    );
    final departures = count(
      'departures',
      RegExp(r'^(WYSTARTOWAŁ|ODLECIAŁ|DEPARTED|TAKEN OFF)'),
    );
    if (arrivals == null || departures == null) return null;
    return NeptunPassengerBoard(
      now,
      arrivals.total,
      departures.total,
      landed: arrivals.completed,
      departed: departures.completed,
    );
  }

  static Future<NeptunPassengerBoard?> fetch(http.Client client) async {
    final response = await client
        .get(
          Uri.parse(lublinPassengerBoardUrl),
          headers: {'Accept': 'text/html', 'Cache-Control': 'no-cache'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.length > 512 * 1024) {
      return null;
    }
    return fromLublinHtml(utf8.decode(response.bodyBytes), DateTime.now());
  }
}
