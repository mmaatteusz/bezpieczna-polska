import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'model.dart';
import 'shelters.dart';

class ShelterPanel extends StatefulWidget {
  final DataRepository repository;
  final String region;
  final ShelterPage? initial;
  final bool online;
  final Future<void> Function(String) openLink;
  const ShelterPanel({
    super.key,
    required this.repository,
    required this.region,
    required this.initial,
    required this.online,
    required this.openLink,
  });
  @override
  State<ShelterPanel> createState() => _ShelterPanelState();
}

class _ShelterPanelState extends State<ShelterPanel> {
  final search = TextEditingController();
  ShelterPage? page;
  bool loading = false, connected = false, nearestLoading = false;
  String? message, nearestMessage;
  NearestSheltersResult? nearest;
  int request = 0;
  @override
  void initState() {
    super.initState();
    page = widget.online
        ? widget.initial ?? widget.repository.cachedShelters(widget.region)
        : widget.repository.cachedShelters(widget.region) ?? widget.initial;
    search.text = page?.query ?? '';
    connected = widget.initial != null && widget.online;
  }

  @override
  void didUpdateWidget(covariant ShelterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (page?.query.isEmpty != false &&
        (page?.offset ?? 0) == 0 &&
        !loading &&
        widget.online &&
        widget.initial?.data['serverTime'] !=
            oldWidget.initial?.data['serverTime'] &&
        widget.initial != null) {
      page = widget.initial;
      connected = widget.online;
    }
    if (!widget.online) {
      connected = false;
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({int offset = 0}) async {
    final ticket = ++request;
    final query = offset == 0 ? search.text.trim() : page?.query ?? '';
    setState(() {
      loading = true;
      message = null;
    });
    try {
      ShelterPage result;
      try {
        result = await widget.repository.refreshShelters(
          widget.region,
          query: query,
          offset: offset,
          version: offset == 0 ? null : page?.version,
        );
      } on ShelterVersionChanged {
        result = await widget.repository.refreshShelters(
          widget.region,
          query: query,
        );
        if (mounted && ticket == request) {
          message = 'PSP zaktualizowała zbiór. Pokazano pierwszą stronę.';
        }
      }
      if (mounted && ticket == request) {
        setState(() {
          page = result;
          connected = true;
        });
      }
    } catch (error) {
      if (mounted && ticket == request) {
        setState(() {
          connected = false;
          message = apiFailureMessage(error);
        });
      }
    } finally {
      if (mounted && ticket == request) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> locateNearest() async {
    if (nearestLoading) return;
    setState(() {
      nearestLoading = true;
      nearestMessage = null;
    });
    try {
      if (widget.repository.api.isEmpty) {
        throw const ApiFailure(ApiFailureKind.notConfigured);
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(
            () => nearestMessage =
                'Włącz lokalizację w telefonie, aby znaleźć najbliższy punkt.',
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(
            () => nearestMessage =
                'Bez zgody na lokalizację nie można policzyć odległości. Możesz nadal wyszukiwać po adresie.',
          );
        }
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(
            () => nearestMessage =
                'Dostęp do lokalizacji jest zablokowany w ustawieniach Androida. Możesz nadal wyszukiwać po adresie.',
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final result = await widget.repository.nearestShelters(
        position.latitude,
        position.longitude,
        limit: 3,
      );
      if (mounted) {
        setState(() {
          nearest = result;
          final state =
              result.health?['healthStatus'] ?? result.health?['state'];
          nearestMessage = result.items.isEmpty
              ? 'Brak punktów schronienia w aktualnym pakiecie danych.'
              : state == 'STALE'
              ? 'Uwaga: najbliższe punkty wyliczono z zapisanej, nieaktualnej kopii wykazu.'
              : state == 'BROKEN' || state == 'DEGRADED'
              ? 'Uwaga: aktualność wykazu nie jest obecnie w pełni potwierdzona.'
              : null;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => nearestMessage =
              'Nie udało się ustalić lokalizacji w wymaganym czasie. Spróbuj ponownie na zewnątrz lub wyszukaj adres ręcznie.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => nearestMessage = apiFailureMessage(error));
      }
    } finally {
      if (mounted) setState(() => nearestLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = page, h = page?.health;
    final fresh = connected && (p?.freshAt(DateTime.now()) ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Punkty schronienia PSP',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Wpis w wykazie nie potwierdza klasy schronu ani możliwości wejścia w tej chwili. Klasy ochrony, pojemności i dostępności dla osób z niepełnosprawnościami nie podano.',
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: nearestLoading ? null : locateNearest,
          icon: nearestLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.near_me_outlined),
          label: const Text('Znajdź najbliższe schronienie'),
        ),
        const Text(
          'Lokalizacja jest pobierana tylko po tym kliknięciu, wyłącznie do obliczenia odległości i nie jest zapisywana.',
        ),
        if (nearestMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(nearestMessage!),
          ),
        if (nearest != null && nearest!.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...nearest!.items.map(
            (item) => Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(item.point.address),
                subtitle: Text(
                  '${item.distanceLabel} • ${item.point.data["municipality"]}\n${item.point.availability}',
                ),
                isThreeLine: true,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: search,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Adres lub gmina',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: loading ? null : (_) => load(),
        ),
        FilledButton.icon(
          onPressed: loading ? null : () => load(),
          icon: const Icon(Icons.search),
          label: const Text('Szukaj punktów'),
        ),
        if (loading) const LinearProgressIndicator(),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message!),
          ),
        if (p == null || p.version == null) ...[
          const SizedBox(height: 16),
          const Text('Brak zweryfikowanego pakietu schronienia'),
          const Text('Brak danych nie oznacza braku punktów w okolicy.'),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            fresh
                ? 'Źródło zsynchronizowane'
                : 'Kopia zapisana — aktualność niepotwierdzona',
          ),
          Text('Ostatnia poprawna synchronizacja: ${stamp(h?["lastSuccess"])}'),
          Text('Dane PSP z: ${h?["dataDate"] ?? "Nie podano"}'),
          Text(
            'Wyniki: ${p.total} • ${regions[widget.region] ?? widget.region}',
          ),
          if (p.query.isNotEmpty) Text('Wyszukiwanie: ${p.query}'),
          if (p.items.isEmpty)
            const Text('Brak wyników dla wybranego zapytania.'),
          ...p.items.map(
            (point) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.address,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${point.data["municipality"]} • ${point.data["county"]}',
                    ),
                    const SizedBox(height: 8),
                    Text(point.availability),
                    Text('Rodzaj wg PSP: ${point.data["sourceType"]}'),
                    Text(
                      'Współrzędne: ${(point.data["latitude"] as num).toStringAsFixed(6)}, ${(point.data["longitude"] as num).toStringAsFixed(6)}',
                    ),
                    Text(
                      point.data['id'] as String,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (p.items.isNotEmpty)
            Text(
              'Pozycje ${p.offset + 1}–${p.offset + p.items.length} z ${p.total}',
            ),
          Wrap(
            spacing: 12,
            children: [
              if (p.offset > 0)
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => load(
                          offset: (p.offset - p.limit).clamp(0, p.total),
                        ),
                  child: const Text('Poprzednie'),
                ),
              if (p.hasMore)
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => load(offset: p.offset + p.limit),
                  child: const Text('Następne'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Offline dostępna jest zapisana strona wyników oraz pierwsza strona z ostatniej synchronizacji regionu. To nie jest pełny wykaz offline.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Źródło: Komenda Główna PSP / dane.gov.pl • CC BY 4.0. Dane przefiltrowano i ujednolicono.',
        ),
        TextButton(
          onPressed: () => widget.openLink(
            'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',
          ),
          child: const Text('Zbiór danych i licencja'),
        ),
        OutlinedButton.icon(
          onPressed: () => widget.openLink('https://gdziesieukryc.pl/'),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Otwórz serwis PSP'),
        ),
      ],
    );
  }
}
