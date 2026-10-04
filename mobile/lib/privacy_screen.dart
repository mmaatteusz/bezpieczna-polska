import 'package:flutter/material.dart';

import 'build_config.dart';

class PrivacyScreen extends StatelessWidget {
  final void Function(String) openLink;
  final String policyUrl;

  const PrivacyScreen({
    super.key,
    required this.openLink,
    this.policyUrl = compiledPrivacyPolicyUrl,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Polityka prywatności')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Jak aplikacja korzysta z danych',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'To skrót informacji o działaniu aplikacji. Pełna polityka zawiera '
          'dane administratora, zasady przechowywania danych i kontakt.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Lokalizacja i okolica\n'
          'Wybrana miejscowość, obserwowane miejsca i ustawienia są zapisane '
          'na telefonie. Zapytania o okolicę i najbliższe schronienia wysyłają '
          'współrzędne wybranego punktu do naszego API. Możesz korzystać '
          'z aplikacji bez zgody na GPS, wybierając miejscowość ręcznie.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Powiadomienia\n'
          'Rejestracja push wysyła do API identyfikator instalacji, token '
          'powiadomień, wersję aplikacji, platformę i wybrane kategorie. '
          'Po włączeniu powiadomień dla obserwowanych miejsc wysyłane i '
          'przechowywane są także ich nazwy, współrzędne i promienie. '
          'Na Androidzie powiadomienia dostarcza Google Firebase Cloud Messaging.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Mapy i nawigacja\n'
          'Mapa online pobiera dane od dostawcy podkładu. Dostawca otrzymuje '
          'adres IP i żądania dotyczące oglądanego obszaru. Wybranie nawigacji '
          'przekazuje punkt docelowy zewnętrznej aplikacji mapowej.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Wyłączenie i usuwanie\n'
          'W ustawieniach powiadomień możesz wyrejestrować urządzenie. '
          'Po potwierdzonym połączeniu z API usuwa to aktywny token i '
          'obserwowane miejsca z rekordu push. Nie oznacza usunięcia całej '
          'historii technicznej ani kopii zapasowych. Odinstalowanie aplikacji '
          'lub odmowa powiadomień w systemie nie zastępują wyrejestrowania. '
          'Usunięcie lekkiego cache nie usuwa ustawień ani danych na serwerze.',
        ),
        const SizedBox(height: 20),
        if (isPublicPrivacyPolicyUrl(policyUrl))
          FilledButton.icon(
            onPressed: () => openLink(policyUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Otwórz pełną politykę prywatności'),
          )
        else
          const Text(
            'Pełna polityka nie została jeszcze skonfigurowana w tym wydaniu '
            'testowym. Ten skrót nie zastępuje pełnej polityki prywatności.',
          ),
      ],
    ),
  );
}
