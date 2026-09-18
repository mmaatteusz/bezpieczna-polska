# Walidacja 0.1.0-alpha.2 — 18.09.2026

Kod został odtworzony po automatycznym usunięciu poprzedniego środowiska. Poniższe wyniki dotyczą nowej kopii, nie utraconej alpha.1.

- TypeScript: kompilacja zakończona powodzeniem.
- Backend: 28 testów, 28 PASS, 0 FAIL (docs/backend-tests.txt).
- Flutter: 14 testów, 14 PASS, 0 FAIL (docs/mobile-tests.txt).
- Analiza Dart: No issues found (docs/flutter-analyze.txt).
- Kontrola wyglądu: obrazy ekranów 390×844 w mobile/test/goldens; obejrzane po wygenerowaniu.
- Test UI obejmuje mapę offline, przejścia między ekranami i potwierdzenie przed otwarciem numeru 112.
- Test 200% tekstu na ekranie 390×844 przechodzi.
- Pobranie danych: RCB i RSO HEALTHY, łącznie 135 zapisów, 18.09.2026 10:53 UTC. Jest to test pobierania, nie ocena aktualnego zagrożenia. Szczegóły docs/ingestion-check.txt.
- Ponowne sprawdzenie w sesji kontynuacji: TypeScript PASS, backend 28/28 PASS, Flutter 14/14 PASS, analiza Dart bez błędów. Flutter 3.47.4 / Dart 3.13.3 / Node.js 24.19.0. Raporty tekstowe w archiwum pochodzą z wcześniejszego przebiegu; wyniki ponownego przebiegu potwierdzono w narzędziach przed utratą plików tymczasowych.
- APK: wznowiono budowanie po instalacji SDK 36 i NDK 28.2.13676358; rozwiązano błąd rozpakowania archiwum oraz konfigurację proxy Gradle. Proces doszedł do `assembleDebug` i pobierania zależności, po czym sesja procesu oraz pliki `/tmp` zniknęły. Brak potwierdzonego APK; nie deklarujemy ukończonego builda.
- GitHub Actions: dołączono skrypty Gradle do wersjonowania, timeouty, weryfikację podpisu APK i sumę SHA-256. Workflow nie został jeszcze uruchomiony na GitHubie.
- PostgreSQL/Docker: konfiguracja przygotowana, nie zweryfikowana w tym środowisku.
- Brak testów na fizycznym telefonie, testów APNs/FCM, podpisu sklepowego i testów iOS.
- GitHub: utworzono prywatne repozytorium https://github.com/mmaatteusz/bezpieczna-polska. Pozostaje puste. Automatyczny przegląd uprawnień zablokował przesłanie archiwum kodu i wymaga bezpośredniego potwierdzenia pliku i celu przez użytkownika.

Nie spełnia gates wydania produkcyjnego. Brakujące integracje wymieniono w README.
