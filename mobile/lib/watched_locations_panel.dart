import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'model.dart';
import 'offline_repository.dart';

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
        () => message = 'Lokalizacja w telefonie jest wyłączona. Możesz wyszukać miasto lub wieś.',
      );
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      setState(
        () => message = 'Bez zgody na lokalizację nie można użyć „Wokół mnie”. Możesz wyszukać miasto lub wieś.',
      );
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      setState(
        () => message = 'Dostęp do lokalizacji jest zablokowany w ustawieniach systemu. Możesz dodać miejsce ręcznie.',
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
        () => message = 'Nie udało się ustalić pozycji w wymaganym czasie. Spróbuj ponownie lub dodaj miejsce ręcznie.',
      );
      return null;
    }
  }

  Future<AroundResult> _aroundWithOffline(
    double latitude,
    double longitude, {
    required double radiusKm,
    String? regionId,
  }) async {
    try {
      if (widget.repository.api.isEmpty) {
        throw const ApiFailure(ApiFailureKind.notConfigured);
      }
      return await widget.repository.around(
        latitude,
        longitude,
        radiusKm: radiusKm,
        regionId: regionId,
      );
    } catch (error) {
      final local = await widget.repository.offlineAround(
        latitude,
        longitude,
        radiusKm: radiusKm,
        regionId: regionId,
      );
      if (local == null) rethrow;
      if (mounted) {
        setState(
          () => message =
              'OFFLINE • wynik policzono wyłącznie z lokalnego pakietu z ${stamp(local.data['offlineSnapshotTimestamp'])}. Współrzędnych nie wysłano. Brak nowych danych nie oznacza bezpieczeństwa.',
        );
      }
      return local;
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
      final value = await _aroundWithOffline(
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
      final value = await _aroundWithOffline(
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
    final place = TextEditingController();
    final label = TextEditingController(
      text: latitude == null ? '' : 'Bieżąca lokalizacja',
    );
    final radius = TextEditingController(text: '20');
    Location? resolved = latitude == null || longitude == null
        ? null
        : Location(latitude: latitude, longitude: longitude);
    String? resolvedName = resolved == null
        ? null
        : 'Bieżąca lokalizacja z GPS';
    var selectedRegion = '';
    var searching = false;
    String? validation;

    String placemarkLabel(Placemark p, String fallback) {
      final parts = <String>[
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.subAdministrativeArea ?? '').trim().isNotEmpty &&
            p.subAdministrativeArea!.trim() != p.locality?.trim())
          p.subAdministrativeArea!.trim(),
        if ((p.administrativeArea ?? '').trim().isNotEmpty)
          p.administrativeArea!.trim(),
      ];
      return parts.isEmpty ? fallback : parts.toSet().join(', ');
    }

    String? regionFromPlacemark(Placemark p) {
      String normalize(String value) => value
          .toLowerCase()
          .replaceAll('województwo', '')
          .replaceAll('woj.', '')
          .replaceAll(RegExp(r'[^a-ząćęłńóśźż]'), '');
      final area = normalize(p.administrativeArea ?? '');
      if (area.isEmpty) return null;
      for (final entry in regions.entries.where((e) => e.key != 'PL')) {
        if (normalize(entry.value) == area) return entry.key;
      }
      return null;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dodaj obserwowane miejsce'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resolved == null) ...[
                  TextField(
                    controller: place,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'Miasto lub wieś',
                      hintText: 'np. Bydgoszcz albo Osielsko',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) async {
                      if (searching || place.text.trim().length < 2) return;
                      setDialogState(() {
                        searching = true;
                        validation = null;
                      });
                      try {
                        final geocoding = Geocoding();
                        final found = await geocoding.locationFromAddress(
                          '${place.text.trim()}, Polska',
                          locale: const Locale('pl', 'PL'),
                        );
                        if (found.isEmpty) throw const FormatException();
                        final candidate = found.first;
                        var name = place.text.trim();
                        try {
                          final marks = await geocoding
                              .placemarkFromCoordinates(
                                candidate.latitude,
                                candidate.longitude,
                                locale: const Locale('pl', 'PL'),
                              );
                          if (marks.isNotEmpty) {
                            name = placemarkLabel(marks.first, name);
                            selectedRegion =
                                regionFromPlacemark(marks.first) ??
                                selectedRegion;
                          }
                        } catch (_) {}
                        setDialogState(() {
                          resolved = candidate;
                          resolvedName = name;
                          if (label.text.trim().isEmpty) {
                            label.text = name.length > 60
                                ? name.substring(0, 60)
                                : name;
                          }
                          searching = false;
                        });
                      } catch (_) {
                        setDialogState(() {
                          searching = false;
                          validation = 'Nie znaleziono tej miejscowości. Dopisz powiat lub województwo i spróbuj ponownie.';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: searching
                        ? null
                        : () async {
                            if (place.text.trim().length < 2) {
                              setDialogState(
                                () =>
                                    validation = 'Wpisz nazwę miasta lub wsi.',
                              );
                              return;
                            }
                            setDialogState(() {
                              searching = true;
                              validation = null;
                            });
                            try {
                              final geocoding = Geocoding();
                              final found = await geocoding.locationFromAddress(
                                '${place.text.trim()}, Polska',
                                locale: const Locale('pl', 'PL'),
                              );
                              if (found.isEmpty) throw const FormatException();
                              final candidate = found.first;
                              var name = place.text.trim();
                              try {
                                final marks = await geocoding
                                    .placemarkFromCoordinates(
                                      candidate.latitude,
                                      candidate.longitude,
                                      locale: const Locale('pl', 'PL'),
                                    );
                                if (marks.isNotEmpty) {
                                  name = placemarkLabel(marks.first, name);
                                  selectedRegion =
                                      regionFromPlacemark(marks.first) ??
                                      selectedRegion;
                                }
                              } catch (_) {}
                              setDialogState(() {
                                resolved = candidate;
                                resolvedName = name;
                                if (label.text.trim().isEmpty) {
                                  label.text = name.length > 60
                                      ? name.substring(0, 60)
                                      : name;
                                }
                                searching = false;
                              });
                            } catch (_) {
                              setDialogState(() {
                                searching = false;
                                validation = 'Nie znaleziono tej miejscowości. Dopisz powiat lub województwo i spróbuj ponownie.';
                              });
                            }
                          },
                    icon: searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore),
                    label: const Text('Znajdź miejsce'),
                  ),
                ],
                if (resolvedName != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(resolvedName!),
                    subtitle: const Text(
                      'Miejsce znalezione i gotowe do zapisu',
                    ),
                    trailing: latitude == null
                        ? IconButton(
                            tooltip: 'Wybierz inne miejsce',
                            onPressed: () => setDialogState(() {
                              resolved = null;
                              resolvedName = null;
                              validation = null;
                            }),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                ],
                TextField(
                  controller: label,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa własna — opcjonalnie',
                    hintText: 'np. Dom, Praca, Rodzina',
                  ),
                ),
                TextField(
                  controller: radius,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Promień alertów w km',
                    hintText: '20',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedRegion),
                  initialValue: selectedRegion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Województwo — wykrywane automatycznie',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Nie ustawiaj'),
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
                  'Aplikacja zapisuje wybrane miejsce lokalnie. Nie zapisuje historii przemieszczania.',
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
              onPressed: resolved == null
                  ? null
                  : () async {
                      final ra = double.tryParse(
                        radius.text.trim().replaceAll(',', '.'),
                      );
                      try {
                        if (ra == null) throw const FormatException();
                        final finalLabel = label.text.trim().isNotEmpty
                            ? label.text.trim()
                            : resolvedName ?? place.text.trim();
                        await widget.repository.addWatchedLocation(
                          label: finalLabel,
                          latitude: resolved!.latitude,
                          longitude: resolved!.longitude,
                          radiusKm: ra,
                          regionId: selectedRegion.isEmpty
                              ? null
                              : selectedRegion,
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
                              : 'Sprawdź nazwę miejsca i promień 1–100 km.';
                        });
                      }
                    },
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
    place.dispose();
    label.dispose();
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
          label: const Text('Dodaj miasto lub wieś'),
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
                'Promień alertów: ${location.radiusKm.toStringAsFixed(0)} km'
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
          'Obserwowane miejsca nie tworzą historii przemieszczania. Ręczne „Sprawdź” wysyła współrzędne i promień do bieżącego zapytania. Jeśli włączysz osobno powiadomienia dla obserwowanych lokalizacji, aktualna lista zapisanych punktów jest synchronizowana do backendu do czasu wyłączenia tej kategorii lub wyrejestrowania push.',
        ),
      ],
    );
  }
}
