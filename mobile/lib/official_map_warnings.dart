import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'model.dart';
import 'warsaw_time.dart';

const _urls = {
  'RSO':
      'https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml',
  'IMGW_METEO': 'https://danepubliczne.imgw.pl/api/data/warningsmeteo',
  'IMGW_HYDRO': 'https://danepubliczne.imgw.pl/api/data/warningshydro',
};

class OfficialWarningFeed {
  final String source;
  final DateTime checkedAt;
  final List<SafetyEvent> events;
  OfficialWarningFeed(this.source, this.checkedAt, this.events);

  String get label => switch (source) {
    'RSO' => 'RSO',
    'IMGW_METEO' => 'IMGW meteo',
    _ => 'IMGW hydro',
  };
}

class OfficialMapWarnings {
  final DataRepository repository;
  OfficialMapWarnings(this.repository);
  final _running = <int, Future<List<OfficialWarningFeed>>>{};
  int? _lastGeneration;
  DateTime? _lastAttempt;

  String _key(String source) => 'map:${repository.api}:warnings:$source';

  List<OfficialWarningFeed> cached() {
    final feeds = <OfficialWarningFeed>[];
    for (final source in _urls.keys) {
      try {
        final value = repository.prefs.getString(_key(source));
        if (value == null) continue;
        final raw = jsonDecode(value) as Map;
        feeds.add(
          OfficialWarningFeed(
            source,
            DateTime.parse(raw['checkedAt'] as String),
            (raw['events'] as List).map(SafetyEvent.parse).toList(),
          ),
        );
      } catch (_) {
        // A broken local copy must not hide other sources.
      }
    }
    return feeds;
  }

  Future<List<OfficialWarningFeed>> refresh({bool force = false}) {
    final generation = repository.dataGeneration;
    final pending = _running[generation];
    if (pending != null) return pending;
    if (!force &&
        generation == _lastGeneration &&
        _lastAttempt != null &&
        DateTime.now().difference(_lastAttempt!) <
            const Duration(seconds: 45)) {
      return Future.value(cached());
    }
    _lastGeneration = generation;
    _lastAttempt = DateTime.now();
    return _running[generation] =
        Future.wait(
              _urls.entries.map((source) => _readFeed(source, generation)),
            )
            .then(
              (_) => generation == repository.dataGeneration
                  ? cached()
                  : <OfficialWarningFeed>[],
            )
            .whenComplete(() {
              _running.remove(generation);
            });
  }

  Future<void> _readFeed(
    MapEntry<String, String> source,
    int generation,
  ) async {
    try {
      final response = await repository.client
          .get(Uri.parse(source.value))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 2 * 1024 * 1024) {
        return;
      }
      final now = DateTime.now().toUtc();
      final text = utf8.decode(response.bodyBytes);
      final events = source.key == 'RSO'
          ? _rsoEvents(text, now)
          : _imgwEvents(text, now, source.key);
      if (generation != repository.dataGeneration) return;
      await repository.prefs.setString(
        _key(source.key),
        jsonEncode({
          'checkedAt': now.toIso8601String(),
          'events': events.map((e) => e.data).toList(),
        }),
      );
    } catch (_) {
      // Keep this source's last successful read, including on a malformed feed.
    }
  }
}

String _region(String name) => regions.entries
    .firstWhere(
      (entry) =>
          entry.key != 'PL' &&
          entry.value.toLowerCase() == name.trim().toLowerCase(),
    )
    .key;

List<SafetyEvent> _rsoEvents(String text, DateTime now) {
  if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(text)) {
    throw const FormatException('Nieobsługiwany dokument RSO');
  }
  final root = XmlDocument.parse(text).rootElement;
  final items = root.findElements('news').toList();
  final total = root.getElement('pagination_info')?.getAttribute('totalItems');
  if (root.name.local != 'newses' ||
      int.tryParse(total ?? '') != items.length ||
      items.length > 2000) {
    throw const FormatException('Niepełna lista RSO');
  }
  final result = <SafetyEvent>[];
  for (final node in items) {
    String field(String key) => node.getElement(key)?.innerText.trim() ?? '';
    final end = field('valid_to');
    if (end.isEmpty) continue;
    final until = parseWarsawWarningTime(end);
    if (!until.isAfter(now)) continue;
    final id = field('id'), title = field('title');
    final from = field('valid_from').isEmpty
        ? null
        : parseWarsawWarningTime(field('valid_from'));
    if (!RegExp(r'^\d+$').hasMatch(id) ||
        title.isEmpty ||
        (from != null && !until.isAfter(from))) {
      throw const FormatException('Niepoprawny komunikat RSO');
    }
    final description = field('content').isEmpty
        ? field('shortcut')
        : field('content');
    final url = 'https://komunikaty.tvp.pl/komunikaty/$id/detale';
    final high = ![
      '',
      '0',
      'false',
      'nie',
      'no',
    ].contains(field('rso_alarm').toLowerCase());
    result.add(
      SafetyEvent.parse({
        'id': 'RSO-$id',
        'title': title,
        'description': description,
        'revision': 1,
        'messageContext': 'UNKNOWN',
        'verification': 'UNVERIFIED',
        'lifecycle': 'ACTIVE',
        'eventType': 'OTHER',
        'severity': high ? 'HIGH' : 'NORMAL',
        'regions': node
            .findAllElements('province')
            .map((p) => _region(p.innerText))
            .toSet()
            .toList(),
        'sources': [
          {
            'id': 'RSO',
            'name': 'Regionalny System Ostrzegania',
            'url': url,
            'tier': 1,
          },
        ],
        'latitude': double.tryParse(field('latitude')),
        'longitude': double.tryParse(field('longitude')),
        'publishedAt': parseWarsawWarningTime(
          field('created_at'),
        ).toIso8601String(),
        'validFrom': from?.toIso8601String(),
        'validTo': until.toIso8601String(),
        'retrievedAt': now.toIso8601String(),
      }),
    );
  }
  return result;
}

List<SafetyEvent> _imgwEvents(String text, DateTime now, String source) {
  final data = jsonDecode(text);
  final meteo = source == 'IMGW_METEO';
  if (data is Map &&
      (data['message'] ==
              'Brak ostrzeżeń ${meteo ? "meteorologicznych" : "hydrologicznych"}' ||
          (data['status'] == false &&
              data['message'] == 'No products were found'))) {
    return [];
  }
  if (data is! List || data.length > 500) {
    throw const FormatException('Niepełna lista IMGW');
  }
  final result = <SafetyEvent>[];
  for (final row in data.cast<Map>()) {
    String field(List<String> keys) => keys
        .map((k) => row[k]?.toString().trim() ?? '')
        .firstWhere((v) => v.isNotEmpty);
    final from = parseWarsawWarningTime(field(['obowiazuje_od', 'data_od']));
    final until = parseWarsawWarningTime(field(['obowiazuje_do', 'data_do']));
    if (!until.isAfter(from)) {
      throw const FormatException('Niepoprawna ważność IMGW');
    }
    if (!until.isAfter(now)) continue;
    final name = field(['nazwa_zdarzenia', 'zdarzenie']),
        office = field(['biuro']);
    final number = ['id', 'numer', 'numer_ostrzezenia', 'nr']
        .map((k) => row[k]?.toString().trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final identity = number.isEmpty
        ? '$office|$name|${from.toIso8601String()}'
        : '$office|${from.year}|$number';
    final id = sha256
        .convert(utf8.encode(identity))
        .toString()
        .substring(0, 24);
    final level = int.parse(field(['stopien', 'stopień']));
    if (!(meteo ? [1, 2, 3] : [-1, 1, 2, 3]).contains(level)) {
      throw const FormatException('Nieznany stopień IMGW');
    }
    final areaIds = <String>{};
    String location;
    if (meteo) {
      final codes = (row['teryt'] as List).cast<String>().toSet();
      if (codes.isEmpty ||
          codes.any(
            (c) =>
                !RegExp(r'^\d{2,7}$').hasMatch(c) ||
                !regions.containsKey(c.substring(0, 2)),
          )) {
        throw const FormatException('Niepoprawny zasięg IMGW');
      }
      areaIds.addAll(codes.map((c) => c.substring(0, 2)));
      location = 'TERYT: ${codes.join(", ")}';
    } else {
      final areas = (row['obszary'] as List).cast<Map>();
      if (areas.isEmpty) throw const FormatException('Brak zasięgu IMGW');
      areaIds.addAll(areas.map((a) => _region(a['wojewodztwo'] as String)));
      location = areas.map((a) => a['opis'] as String).toSet().join('; ');
    }
    final comment = row['komentarz'] ?? row['uwagi'];
    result.add(
      SafetyEvent.parse({
        'id': '$source-$id',
        'title': 'IMGW: $name${level > 0 ? " — stopień $level" : ""}',
        'description': [
          field(['tresc', 'przebieg']),
          if (comment is String && comment.trim().isNotEmpty) comment.trim(),
        ].join('\n\n'),
        'revision': 1,
        'messageContext': 'ACTUAL',
        'verification': 'CONFIRMED',
        'lifecycle': 'ACTIVE',
        'eventType': 'WEATHER',
        'severity': level == 3
            ? 'CRITICAL'
            : level == 2
            ? 'HIGH'
            : 'NORMAL',
        'regions': areaIds.toList(),
        'locationText': location,
        'sources': [
          {'id': source, 'name': 'IMGW-PIB', 'url': _urls[source], 'tier': 1},
        ],
        'publishedAt': parseWarsawWarningTime(
          field(['opublikowano']),
        ).toIso8601String(),
        'validFrom': from.toIso8601String(),
        'validTo': until.toIso8601String(),
        'retrievedAt': now.toIso8601String(),
      }),
    );
  }
  return result;
}
