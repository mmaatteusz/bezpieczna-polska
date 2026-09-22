import 'dart:async';

import 'package:flutter/material.dart';

import 'model.dart';
import 'offline_packages.dart';
import 'offline_repository.dart';

class OfflineDataScreen extends StatefulWidget {
  final DataRepository repository;
  const OfflineDataScreen({super.key, required this.repository});

  @override
  State<OfflineDataScreen> createState() => _OfflineDataScreenState();
}

class _OfflineDataScreenState extends State<OfflineDataScreen> {
  List<OfflinePackageDescriptor> packages = const [];
  bool loading = true;
  String? busyRegion;
  String? message;
  int usedBytes = 0;
  String selectedRegion = '04';

  @override
  void initState() {
    super.initState();
    selectedRegion = widget.repository.region;
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final list = await widget.repository.listOfflinePackages();
      final used = await widget.repository.offlineUsedBytes();
      if (!mounted) return;
      setState(() {
        packages = list;
        usedBytes = used;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          message = 'Nie udało się odczytać magazynu offline.';
        });
      }
    }
  }

  Future<void> _download(String regionId) async {
    if (busyRegion != null) return;
    setState(() {
      busyRegion = regionId;
      message = null;
    });
    try {
      final package = await widget.repository.downloadOfflinePackage(regionId);
      if (!mounted) return;
      setState(
        () => message =
            'Pakiet ${regions[regionId] ?? regionId} zapisany atomowo. Snapshot: ${stamp(package.snapshotTimestamp.toIso8601String())}.',
      );
    } on OfflinePackageException catch (error) {
      if (!mounted) return;
      setState(() {
        message = switch (error.code) {
          'PACKAGE_TOO_LARGE' || 'SIZE_BOUNDS' =>
            'Pakiet przekracza bezpieczny limit urządzenia. Cała Polska może wymagać osobnego rozwiązania z większym magazynem.',
          'STORAGE_LIMIT' || 'STORAGE_LIMIT_PRESERVE_LKG' =>
            'Brak miejsca w limicie pakietów offline. Zachowano poprzedni last-known-good.',
          _ =>
            'Pakiet nie został aktywowany (${error.code}). Poprzedni last-known-good pozostał bez zmian.',
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => message =
            '${apiFailureMessage(error)} Poprzedni pakiet nie został naruszony.',
      );
    } finally {
      if (mounted) {
        setState(() => busyRegion = null);
        await _reload();
      }
    }
  }

  Future<void> _delete(String regionId) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Usunąć pakiet offline?'),
        content: Text(regions[regionId] ?? regionId),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.repository.deleteOfflinePackage(regionId);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(title: const Text('Dane offline')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pakiet regionu',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pakiet zachowuje snapshot statusu, Eventy i Incidenty, stan źródeł, stopnie alarmowe, PAA, pełny katalog schronień regionu, lokalne overlaye mapy i konfigurację obserwowanych miejsc.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Offline nigdy nie oznacza LIVE. Brak nowych danych nie potwierdza bezpieczeństwa. Alarmy Ukrainy i NEPTUN zachowują własny, niezależny lifecycle.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Podkład OpenFreeMap nie jest częścią pakietu. Bez internetu aplikacja nadal ma lokalne dane i overlaye; podkład bazowy może być niedostępny.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRegion,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Region do przygotowania',
                    ),
                    items: regions.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: busyRegion == null
                        ? (value) =>
                            setState(() => selectedRegion = value ?? '04')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busyRegion == null
                        ? () => _download(selectedRegion)
                        : null,
                    icon: busyRegion == null
                        ? const Icon(Icons.download_outlined)
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                    label: const Text('Pobierz / odśwież pakiet'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Zajęte miejsce: ${formatOfflineBytes(usedBytes)} / ${formatOfflineBytes(OfflinePackageStore.maxTotalBytes)} • maks. ${OfflinePackageStore.maxPackages} pakietów',
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!),
          ],
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(),
          if (!loading && packages.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.offline_pin_outlined),
                title: Text('Brak zapisanych pakietów'),
                subtitle: Text(
                  'Pobierz region przed utratą internetu. Dotychczasowe lekkie cache nadal działają niezależnie.',
                ),
              ),
            ),
          ...packages.map((descriptor) {
            final package = descriptor.package;
            final manifest = package?.manifest;
            final state = descriptor.package == null
                ? descriptor.state
                : package!.stateAt(now);
            final sourceMap = manifest?['sourceTimestamps'];
            final sourceRows = sourceMap is Map
                ? sourceMap.entries.toList()
                : <MapEntry<dynamic, dynamic>>[];
            return Card(
              child: ExpansionTile(
                leading: Icon(
                  state == OfflinePackageState.current
                      ? Icons.offline_pin
                      : state == OfflinePackageState.stale
                      ? Icons.schedule
                      : Icons.warning_amber_outlined,
                ),
                title: Text(regions[descriptor.regionId] ?? descriptor.regionId),
                subtitle: Text(
                  '${offlinePackageStateLabel(state)} • ${formatOfflineBytes(descriptor.sizeBytes)}\nPobrano: ${stamp(descriptor.createdAt?.toIso8601String())} • wiek: ${formatOfflineAge(descriptor.createdAt, now)}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                children: [
                  if (package != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Snapshot danych: ${stamp(package.snapshotTimestamp.toIso8601String())}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Schema: ${manifest?['schemaVersion']} • app: ${manifest?['appVersion']} • backend: ${manifest?['backendVersion'] ?? 'nie podano'}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Schronienia: ${package.shelters.length} • wersja: ${package.shelterVersion ?? 'brak'}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Warstwy: ${package.layers.join(', ')}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Składniki: ${package.components.join(', ')}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Checksum: ${manifest?['checksum']}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Stan źródeł w chwili snapshotu:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...sourceRows.take(20).map(
                      (entry) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${entry.key}: ${entry.value is Map ? entry.value['state'] : 'UNKNOWN'} • ${entry.value is Map ? stamp(entry.value['lastSuccess']) : 'Nie podano'}',
                        ),
                      ),
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pakiet nie będzie używany. Błąd: ${descriptor.errorCode ?? 'nieznany'}. Pobierz go ponownie.',
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: busyRegion == null
                            ? () => _download(descriptor.regionId)
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Odśwież'),
                      ),
                      TextButton.icon(
                        onPressed: busyRegion == null
                            ? () => _delete(descriptor.regionId)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Usuń'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}