import 'dart:async';

import 'package:flutter/material.dart';

import 'model.dart';
import 'event_details.dart';

/// Keeps the selected identity when offline, and resolves it again on resume.
class PushAlertPage extends StatefulWidget {
  final String eventId;
  final DataRepository repository;
  final Future<void> Function(String) openLink;
  const PushAlertPage({
    super.key,
    required this.eventId,
    required this.repository,
    required this.openLink,
  });
  @override
  State<PushAlertPage> createState() => _PushAlertPageState();
}

class _PushAlertPageState extends State<PushAlertPage>
    with WidgetsBindingObserver {
  SafetyEvent? event;
  bool loading = true, offline = false, missing = false;
  Timer? retry;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    event = widget.repository.cachedPushEvent(widget.eventId);
    unawaited(load());
    retry = Timer.periodic(const Duration(seconds: 15), (_) {
      if (offline &&
          !loading &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        unawaited(load());
    });
  }

  @override
  void dispose() {
    retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !loading) unawaited(load());
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final latest = await widget.repository.pushEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        event = latest;
        missing = latest == null;
        offline = false;
      });
    } catch (_) {
      if (mounted) setState(() => offline = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: event == null
        ? AppBar(title: const Text('Komunikat z powiadomienia'))
        : null,
    body: SafeArea(
      child: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          if (offline)
            MaterialBanner(
              content: Text(
                event == null
                    ? 'Brak połączenia. Zachowano wybrany komunikat; ponowimy pobranie po odzyskaniu internetu.'
                    : 'Dane zapisane na telefonie. Aktualność ostrzeżenia nie została potwierdzona.',
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : load,
                  child: const Text('Ponów'),
                ),
              ],
            ),
          if (!loading && !offline && event != null)
            TextButton.icon(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              label: const Text('Sprawdź aktualność'),
            ),
          if (event != null)
            Expanded(
              child: EventDetailsPage(
                key: ValueKey('${event!.id}:${event!.revision}:$offline'),
                event: event!,
                repository: widget.repository,
                openLink: widget.openLink,
              ),
            )
          else
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    missing
                        ? 'Ten komunikat nie jest już dostępny. Brak komunikatu nie potwierdza bezpieczeństwa.'
                        : loading
                        ? 'Pobieranie właściwego komunikatu…'
                        : 'Treść komunikatu wymaga połączenia z internetem.',
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
