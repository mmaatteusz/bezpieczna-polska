import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'model.dart';

class WatchedLocationsScreen extends StatelessWidget {
  final DataRepository repository;
  final Future<void> Function()? onPreferencesChanged;
  const WatchedLocationsScreen({
    super.key,
    required this.repository,
    this.onPreferencesChanged,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wokół mnie')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        WatchedLocationsPanel(
          repository: repository,
          onPreferencesChanged: onPreferencesChanged,
        ),
      ],
    ),
  );
}

class WatchedLocationsPanel extends StatefulWidget {
  final DataRepository repository;
  final Future<void> Function()? onPreferencesChanged;
  const WatchedLocationsPanel({
    super.key,
    required this.repository,
    this.onPreferencesChanged,
  });

  @override
  State<WatchedLocationsPanel> createState() => _WatchedLocationsPanelState();
}

class _WatchedLocationsPanelState extends State<WatchedLocationsPanel> {
  bool loading = false;
  String? message, resultLabel;
  AroundResult? result;

  Future<Position?> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(
        () => message =
            'Lokalizacja w telefonie jest wyłączona. Możesz dodać miejsce ręcznie.',
      );
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      setState(
        () => message =
            'Bez zgody na lokalizację nie można użyć „Wokół mnie”. Możesz dodać miejsce ręcznie.',
      );
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      setState(
        () => message =
            'Dostęp do lokalizacji jest zablokowany w ustawieniach systemu. Możesz dodać miejsce ręcznie.',
      );
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      setState(
        () => message =
            'Nie udało się ustalić pozycji w wymaganym czasie. Spróbuj ponownie lub dodaj miejsce ręcznie.',
      );
      return null;
    }
  }

  Future<void> _check({
    required String label,
    required double latitude,
    required double longitude,
    required double radiusKm,
    String? regionId,
  }) async {
    if (loading) return;
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final value = await widget.repository.around(
        latitude,
        longitude,
        radiusKm: radiusKm,
        regionId: regionId,
      );
      if (!mounted) return;
      setState(() {
        result = value;
        resultLabel = label;
      });
    } catch (error) {
      if (mounted) setState(() => message = apiFailureMessage(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _checkCurrent() async {
    if (loading) return;
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final p = await _position();
      if (p == null || !mounted) return;
      final value = await widget.repository.around(
        p.latitude,
        p.longitude,
        radiusKm: 20,
      );
      if (!mounted) return;
      setState(() {
        result = value;
        resultLabel = 'Bieżąca lokalizacja';
      });
    } catch (error) {
      if (mounted) setState(() => message = apiFailureMessage(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _add({double? latitude, double? longitude}) async {
    final label = TextEditingController();
    final lat = TextEditingController(
      text: latitude == null ? '' : latitude.toStringAsFixed(6),
    );
    final lon = TextEditingController(
      text: longitude == null ? '' : longitude.toStringAsFixed(6),
    );
    final radius = TextEditingController(text: '20');
    var selectedRegion = '';
    String? validation;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dodaj obserwowane miejsce'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa, np. Dom / Praca / Rodzina',
                  ),
                ),
                TextField(
                  controller: lat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Szerokość geograficzna',
                  ),
                ),
                TextField(
                  controller: lon,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Długość geograficzna',
                  ),
                ),
                TextField(
                  controller: radius,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Promień w km (1–100)',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedRegion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kontekst wojewódzki — opcjonalny',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Bez kontekstu regionalnego'),
                    ),
                    ...regions.entries
                        .where((e) => e.key != 'PL')
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedRegion = v ?? ''),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Miejsce zostanie zapisane tylko na tym urządzeniu. Backend otrzyma jego współrzędne dopiero, gdy ręcznie wybierzesz „Sprawdź”.',
                ),
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Text(validation!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () async {
                final la = double.tryParse(
                  lat.text.trim().replaceAll(',', '.'),
                );
                final lo = double.tryParse(
                  lon.text.trim().replaceAll(',', '.'),
                );
                final ra = double.tryParse(
                  radius.text.trim().replaceAll(',', '.'),
                );
                try {
                  if (la == null || lo == null || ra == null) {
                    throw const FormatException();
                  }
                  await widget.repository.addWatchedLocation(
                    label: label.text,
                    latitude: la,
                    longitude: lo,
                    radiusKm: ra,
                    regionId: selectedRegion.isEmpty ? null : selectedRegion,
                  );
                  final sync = widget.onPreferencesChanged;
                  if (sync != null) unawaited(sync());
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  setDialogState(() {
                    validation = error is StateError
                        ? 'Można zapisać maksymalnie 20 lokalizacji.'
                        : 'Sprawdź nazwę, współrzędne i promień 1–100 km.';
                  });
                }
              },
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    lat.dispose();
    lon.dispose();
    radius.dispose();
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _addCurrent() async {
    if (loading) return;
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final p = await _position();
      if (p != null && mounted) {
        await _add(latitude: p.latitude, longitude: p.longitude);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _remove(WatchedLocation location) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć obserwowane miejsce?'),
        content: Text(location.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.repository.removeWatchedLocation(location.id);
      final sync = widget.onPreferencesChanged;
      if (sync != null) unawaited(sync());
      if (mounted) setState(() {});
    }
  }

  Widget _resultCard() {
    final value = result;
    if (value == null) return const SizedBox.shrink();
    final coverage = Map<String, dynamic>.from(value.data['coverage'] as Map);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resultLabel ?? 'Wybrana lokalizacja',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Promień: ${value.radiusKm.toStringAsFixed(0)} km'),
            const SizedBox(height: 12),
            Text(
              'Zdarzenia z potwierdzoną geometrią: ${value.nearbyEvents.length}',
            ),
            if (value.nearbyEvents.isEmpty)
              const Text(
                'Brak znalezionych zdarzeń z geometrią nie potwierdza braku zagrożeń w okolicy.',
              ),
            ...value.nearbyEvents.map(
              (row) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(row.event.title),
                subtitle: Text('${row.distanceLabel} • ${row.event.badge}'),
              ),
            ),
            if (value.regionId != null) ...[
              const Divider(),
              Text(
                'Kontekst: ${regions[value.regionId] ?? value.regionId}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (value.regionalEvents.isEmpty)
                const Text(
                  'Brak pasujących komunikatów o jawnym zakresie krajowym lub wojewódzkim.',
                ),
              ...value.regionalEvents.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.public_outlined),
                  title: Text(e.title),
                  subtitle: const Text(
                    'Dotyczy regionu — odległość nie jest wyliczana.',
                  ),
                ),
              ),
            ],
            const Divider(),
            Text(
              'Najbliższe punkty schronienia',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (value.nearestShelters.isEmpty)
              const Text('Brak punktów w aktualnie dostępnej kopii wykazu.'),
            ...value.nearestShelters.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_work_outlined),
                title: Text(item.point.address),
                subtitle: Text(item.distanceLabel),
              ),
            ),
            const Divider(),
            Text(
              coverage['statement'] as String,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watched = widget.repository.watchedLocations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Wokół mnie', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'GPS jest używany tylko po naciśnięciu przycisku. Aplikacja nie uruchamia ciągłego śledzenia ani nie zapisuje historii ruchu.',
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: loading ? null : _checkCurrent,
          icon: const Icon(Icons.my_location_outlined),
          label: const Text('Sprawdź wokół mnie • 20 km'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: loading ? null : _addCurrent,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Zapisz bieżącą lokalizację'),
        ),
        OutlinedButton.icon(
          onPressed: loading ? null : () => _add(),
          icon: const Icon(Icons.edit_location_alt_outlined),
          label: const Text('Dodaj miejsce ręcznie'),
        ),
        if (loading) const LinearProgressIndicator(),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message!),
          ),
        const SizedBox(height: 16),
        Text(
          'Obserwowane lokalizacje',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (watched.isEmpty)
          const Text(
            'Nie zapisano miejsc. Możesz dodać dom, pracę, rodzinę, szkołę lub inne ważne miejsce.',
          ),
        ...watched.map(
          (location) => Card(
            child: ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: Text(location.label),
              subtitle: Text(
                '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)} • ${location.radiusKm.toStringAsFixed(0)} km'
                '${location.regionId == null ? '' : ' • ${regions[location.regionId]}'}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'check') {
                    unawaited(
                      _check(
                        label: location.label,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        radiusKm: location.radiusKm,
                        regionId: location.regionId,
                      ),
                    );
                  } else if (value == 'delete') {
                    unawaited(_remove(location));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'check', child: Text('Sprawdź')),
                  PopupMenuItem(value: 'delete', child: Text('Usuń')),
                ],
              ),
              onTap: loading
                  ? null
                  : () => _check(
                      label: location.label,
                      latitude: location.latitude,
                      longitude: location.longitude,
                      radiusKm: location.radiusKm,
                      regionId: location.regionId,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _resultCard(),
        const SizedBox(height: 12),
        const Text(
          'Obserwowane miejsca są przechowywane lokalnie. Nie są kontem, telemetrią ani historią przemieszczania. Sprawdzenie miejsca wysyła do backendu tylko jego współrzędne i promień potrzebne do bieżącego zapytania.',
        ),
      ],
    );
  }
}
