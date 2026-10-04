# Android: testy z użytkownikami przed publikacją

Stan początkowy wszystkich prób: **NOT_TESTED**. Test jednostkowy, widgetowy,
emulator lub pre-launch report nie zastępują użytkownika na fizycznym telefonie.
Testować oryginalny kandydat produkcyjny, podając SHA-256, versionCode,
model telefonu, Android/API, datę i dowody. Używać syntetycznych obserwowanych
miejsc; w zrzutach/logach zasłaniać dane osobiste, tokeny i sekrety.

| Próba | Sposób | Warunek zaliczenia |
| --- | --- | --- |
| Duży tekst i ekran | Maksymalny font systemowy, co najmniej 200%, mały ekran, większy rozmiar wyświetlania; Start, Alerty/szczegóły, mapa/pop-up, ustawienia/push/polityka | Bez overflow/crasha, wszystkie działania osiągalne, tekst czytelny i przewijalny; żadnego wyłączania skalowania fontu |
| TalkBack | Wszystkie podstawowe zadania od startu, bez patrzenia na ekran | Zrozumiałe etykiety, kolejność fokusu, stan przełączników; powrót z mapy i dostęp do tekstowych szczegółów; kolor nie jest jedyną informacją |
| Odmowa GPS | Świeża instalacja, odmowa; potem trwała odmowa i GPS wyłączony | Brak zapętlenia próśb; ręczny wybór miejscowości; brak fałszywego statusu okolicy; jasna informacja o niedostępnej odległości |
| Odmowa powiadomień | Android 13+, odmowa przy pierwszym uruchomieniu; cofnięcie zgody po rejestracji | Aplikacja działa; nie pokazuje nieprawdziwego stanu gotowości push; ponowne włączenie działa; zbadać stan backendu i SDK |
| Słaba sieć | Wysokie opóźnienie, przerwanie podczas pobrania, przełączanie Wi-Fi/LTE, błąd API | Brak bezterminowego spinnera/crasha; widoczna świeżość i dane zachowane; błąd zmiany preferencji nie udaje sukcesu serwera |
| Mapa przez 45 minut | Przesuwanie/zoom, zmiana warstw i regionów, NEPTUN, pop-up schronu; dziesięć cykli tło/powrót | Brak ANR/crasha, brak narastającej blokady interakcji; pomiar pamięci, temperatury/baterii i ruchu sieciowego z zapisanymi wynikami |
| Offline po restarcie | Pobrany region, zamknąć aplikację, restart telefonu w trybie samolotowym | Dane rzeczywiście odczytane; brak udawania mapy online; jasne ograniczenia podkładu i świeżości |
| Prywatność | Włączenie/wyłączenie obserwowanych miejsc i unregister online/offline | Zgodność UI z żądaniem/rekordem backendu; token/lokalizacje wyczyszczone po sukcesie; brak sekretów w logach |
| Aktualizacja | Poprzednie publiczne wydanie → dokładny kandydat bez uninstall | Zachowane lokalizacje/ustawienia, działający push i otwarcie alertu; zgodność podpisów i package |

Każde zgłoszenie: zadanie użytkownika, kroki, oczekiwany/rzeczywisty wynik,
wersja/model/API, materiał dowodowy, poziom ważności, poprawka/PR i ponowny test.
Nie prosić testerów o eksport tokenów Firebase ani sekretów urządzenia.

## Zamknięty test Google Play

Dla osobistych kont utworzonych po 13.11.2023 Google wymaga co najmniej
12 testerów zapisanych do zamkniętego testu nieprzerwanie przez 14 dni
przed wnioskiem o dostęp do produkcji. To warunek udziału, nie obietnica
automatycznego dopuszczenia aplikacji ani wymóg codziennego otwierania.
Sam udział kont bez informacji o rzeczywistym testowaniu nie dowodzi jakości.

Zebrać dobrowolnie 15–20 rzeczywistych osób jako zapas na rezygnacje, zapewnić
różne telefony i poziomy doświadczenia. W Play ustawić listę/grupę, opublikować
closed testing, przekazać link opt-in i instalacji. Każda osoba musi dołączyć
do testu; samo dodanie adresu do listy nie jest opt-in. Obserwować licznik w Play,
zbierać uwagi i zapisywać poprawki. Po spełnieniu wymogu złożyć wniosek,
uczciwie opisując użycie funkcji, feedback i gotowość. Nie tworzyć fikcyjnych
kont ani nie zastępować rzeczywistych testerów automatyzacją.

Podział pracy: dni 1–3 onboarding/uprawnienia i zadania bazowe; 4–7 mapa,
dostępność i słaba sieć; 8–11 offline/push/aktualizacje; 12–14 poprawki i
ponowne próby. Osoby z TalkBack/dużym fontem powinny przetestować realne zadania.
Pre-launch report wykorzystać dodatkowo; wynik przeanalizować przed wnioskiem.

## Awarie

W kodzie brak Crashlytics/Sentry. To nie jest samo w sobie wymóg Google Play.
Na pierwszym torze testowym wykorzystać Android vitals/pre-launch report,
feedback testerów i kontrolowane logi urządzenia. Wdrożenie zdalnego raportera
wymaga konfiguracji projektu, opisania nowego przepływu danych, retencji i
aktualizacji polityki/Data safety. Nie dołączać do raportów współrzędnych,
FCM tokenów, installationId ani sekretów zarządzania bez wyraźnej potrzeby.

Źródło: https://support.google.com/googleplay/android-developer/answer/14151465
(sprawdzone 4.10.2026).
