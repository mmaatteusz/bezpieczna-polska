import 'package:flutter/material.dart';

import 'model.dart';

class SecurityLevel {
  final Map<String, dynamic> data;
  SecurityLevel._(this.data);
  factory SecurityLevel.parse(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    if (!['ALFA', 'BRAVO', 'CHARLIE', 'DELTA'].contains(m['level']) ||
        !['PHYSICAL', 'CRP'].contains(m['type']) ||
        ![
          'NATIONAL',
          'REGIONAL',
          'INFRASTRUCTURE',
          'EXTRATERRITORIAL_INFRASTRUCTURE',
        ].contains(m['scope']) ||
        m['isActive'] is! bool ||
        m['regions'] is! List) {
      throw const FormatException('Niepoprawny stopień alarmowy');
    }
    for (final key in [
      'id',
      'area',
      'description',
      'issuedBy',
      'sourceUrl',
      'rawSourceId',
      'publishedAt',
    ]) {
      if (m[key] is! String || (m[key] as String).isEmpty) {
        throw const FormatException('Niepełny stopień alarmowy');
      }
    }
    final source = Uri.parse(m['sourceUrl'] as String);
    if (source.scheme != 'https' ||
        source.host != 'www.gov.pl' ||
        !source.path.startsWith('/web/rcb/') ||
        source.userInfo.isNotEmpty) {
      throw const FormatException('Niepoprawne źródło stopnia');
    }
    final start = DateTime.parse(m['validFrom'] as String),
        end = DateTime.parse(m['validTo'] as String);
    if (!end.isAfter(start)) {
      throw const FormatException('Niepoprawny termin');
    }
    return SecurityLevel._(m);
  }
  String get label => '${data['level']}${data['type'] == 'CRP' ? '-CRP' : ''}';
  bool validAt(DateTime now) =>
      !now.isBefore(DateTime.parse(data['validFrom'] as String)) &&
      !now.isAfter(DateTime.parse(data['validTo'] as String));
}

bool levelsFresh(Map<String, dynamic>? data, bool online, DateTime now) {
  if (!online || data == null || data['securityLevelsStatus'] != 'AVAILABLE') {
    return false;
  }
  final sources = data['sources'] as List? ?? [];
  for (final raw in sources) {
    final h = raw as Map;
    if (h['id'] != 'LEVELS') {
      continue;
    }
    final last = DateTime.tryParse(h['lastSuccess'] as String? ?? '');
    return h['state'] == 'HEALTHY' &&
        last != null &&
        !last.isAfter(now.add(const Duration(seconds: 30))) &&
        now.difference(last).inSeconds < (h['maxAgeSeconds'] as num);
  }
  return false;
}

class SecurityLevelsPanel extends StatelessWidget {
  final Snapshot? snapshot;
  final bool online;
  final void Function(String) openSource;
  final DateTime? now;
  const SecurityLevelsPanel({
    super.key,
    required this.snapshot,
    required this.online,
    required this.openSource,
    this.now,
  });
  @override
  Widget build(BuildContext context) {
    final time = now ?? DateTime.now(), data = snapshot?.data;
    final fresh = levelsFresh(data, online, time);
    final items = (data?['securityLevels'] as List? ?? [])
        .map(SecurityLevel.parse)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stopnie alarmowe',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Gotowość służb i administracji. Sam stopień nie oznacza bezpośredniego zagrożenia dla mieszkańca.',
            ),
            const SizedBox(height: 8),
            Text(
              fresh
                  ? 'Dane pobrane z RCB'
                  : items.isEmpty
                  ? 'Brak potwierdzonych aktualnych danych'
                  : 'Ostatnie zapisane dane',
            ),
            Text(
              'Aktualność: ${stamp(data?['securityLevelsLastSuccess'])}${fresh ? '' : ' — niepotwierdzona'}',
            ),
            if (items.isEmpty)
              const Text(
                'Brak wpisów nie potwierdza braku obowiązujących stopni.',
              ),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(item.data['area'] as String),
                    if (item.data['type'] == 'CRP')
                      const Text('Cyberprzestrzeń — systemy teleinformatyczne'),
                    Text(
                      'Od: ${stamp(item.data['validFrom'])}\nObowiązuje do: ${stamp(item.data['validTo'])}',
                    ),
                    if (!item.validAt(time))
                      const Text(
                        'Zapisany termin nie obejmuje bieżącej chwili',
                      ),
                    TextButton(
                      onPressed: () =>
                          openSource(item.data['sourceUrl'] as String),
                      child: const Text('Otwórz oficjalne źródło'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
