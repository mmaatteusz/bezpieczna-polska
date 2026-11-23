import 'package:bezpieczna_polska/neptun_passenger_board.dart';
import 'package:flutter_test/flutter_test.dart';

String row(String day, String flight, String status) =>
    '<div role="row" class="flight-row-grid"><div role="cell">09:00</div>'
    '<div role="cell">$day</div><div role="cell">Kierunek</div>'
    '<div role="cell">$flight</div><div role="cell">Linia</div>'
    '<div role="cell">$status</div></div>';

String table(String type, List<String> rows) =>
    '<section id="$type-table"><div role="table">${rows.join()}</div></section>';

void main() {
  test(
    'airport marker uses only deduplicated passenger totals for the Warsaw date',
    () {
      const day = '22/11/2026';
      final now = DateTime.utc(2026, 11, 21, 23, 30);
      final arrivals = table('arrivals', [
        row(day, 'LO3966', 'WYLĄDOWAŁ'),
        row(day, 'LO3966', 'WYLĄDOWAŁ'),
        row(day, 'FR495', 'ODWOŁANY'),
        row('21/11/2026', 'FR499', 'WYLĄDOWAŁ'),
        row(day, 'ABC', 'ROZKŁADOWO'),
      ]);
      final departures = table('departures', [
        row(day, 'LO3965', 'WYSTARTOWAŁ'),
        row(day, 'W92065', 'ROZKŁADOWO'),
      ]);
      final board = NeptunPassengerBoard.fromLublinHtml(
        arrivals + departures,
        now,
      )!;
      expect(board.arrivals, 1);
      expect(board.landed, 1);
      expect(board.departures, 2);
      expect(board.departed, 1);
      expect(board.isCurrent(now.add(const Duration(minutes: 5))), isFalse);
      expect(NeptunPassengerBoard.fromLublinHtml(arrivals, now), isNull);
    },
  );
}
