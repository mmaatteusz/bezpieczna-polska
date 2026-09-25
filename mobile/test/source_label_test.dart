import 'package:flutter_test/flutter_test.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/ui/safety_event_card.dart';

SafetyEvent eventWith(
  List<Map<String, dynamic>> sources, {
  Map<String, dynamic>? incident,
}) => SafetyEvent({
  'regions': ['04'],
  'sources': sources,
  if (incident != null) '_incident': incident,
});

void main() {
  test('regional RSO item is labelled as WCZK through RSO', () {
    final event = eventWith([
      {'id': 'RSO', 'name': 'Regionalny System Ostrzegania'},
    ]);
    expect(safetySourceLabel(event), 'WCZK • przez RSO');
    expect(independentSourceCount(event), 1);
  });

  test('RSO plus WCZK mirror remains one independent publisher', () {
    final event = eventWith([
      {'id': 'RSO', 'name': 'Regionalny System Ostrzegania'},
      {'id': 'WCZK-18', 'name': 'WCZK — Podkarpackie'},
    ]);
    expect(safetySourceLabel(event), 'WCZK / RSO • ten sam komunikat');
    expect(independentSourceCount(event), 1);
  });

  test('backend incident source count is authoritative in UI', () {
    final event = eventWith(
      [
        {'id': 'RCB', 'name': 'RCB'},
        {'id': 'RSO', 'name': 'RSO'},
        {'id': 'WCZK-18', 'name': 'WCZK'},
      ],
      incident: {'sourceCount': 2},
    );
    expect(independentSourceCount(event), 2);
  });
}
