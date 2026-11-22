import 'package:flutter/material.dart';

import '../model.dart';
import '../shelter_map.dart';

class SafetyMapScreen extends StatelessWidget {
  final DataRepository repository;
  final Snapshot? snapshot;
  final Snapshot? nationalSnapshot;
  final List<SafetyEvent> events;
  final bool online;
  final bool active;
  final String region;
  final void Function(SafetyEvent) onOpenEvent;
  final Future<void> Function(String) openLink;

  const SafetyMapScreen({
    super.key,
    required this.repository,
    required this.snapshot,
    required this.nationalSnapshot,
    required this.events,
    required this.online,
    required this.active,
    required this.region,
    required this.onOpenEvent,
    required this.openLink,
  });

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('map'),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
    children: [
      ShelterMap(
        snapshot: snapshot?.region == 'PL' ? snapshot : nationalSnapshot,
        active: active,
        radiation: snapshot?.data['radiation'],
        radiationOnline: online,
        events: events,
        watchedLocations: repository.watchedLocations,
        openEvent: onOpenEvent,
        key: ValueKey('map:${repository.api}:$region'),
        repository: repository,
        region: region,
        ukraine: false,
        openLink: openLink,
      ),
    ],
  );
}
