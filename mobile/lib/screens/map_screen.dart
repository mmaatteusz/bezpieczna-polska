import 'package:flutter/material.dart';

import '../model.dart';
import '../shelter_map.dart';

class SafetyMapScreen extends StatelessWidget {
  final DataRepository repository;
  final Snapshot? snapshot;
  final List<SafetyEvent> events;
  final bool online;
  final String region;
  final void Function(SafetyEvent) onOpenEvent;
  final Future<void> Function(String) openLink;

  const SafetyMapScreen({
    super.key,
    required this.repository,
    required this.snapshot,
    required this.events,
    required this.online,
    required this.region,
    required this.onOpenEvent,
    required this.openLink,
  });

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('map'),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
    children: [
      ShelterMap(
        radiation: snapshot?.data['radiation'],
        radiationOnline: online,
        events: events,
        watchedLocations: repository.watchedLocations,
        openEvent: onOpenEvent,
        key: ValueKey(
          'map:' +
              repository.api +
              ':' +
              region +
              ':' +
              repository.dataGeneration.toString() +
              ':' +
              repository.watchedLocations.length.toString(),
        ),
        repository: repository,
        region: region,
        ukraine: false,
        openLink: openLink,
      ),
      const SizedBox(height: 10),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Warstwy mapy obejmują zdarzenia, punkty schronienia i dane PAA. '
          'GPS jest używany tylko po Twojej akcji.',
        ),
      ),
    ],
  );
}
