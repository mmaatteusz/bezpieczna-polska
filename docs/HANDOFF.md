# Stan kontynuacji — 18.09.2026

## GitHub

Utworzono prywatne repozytorium: https://github.com/mmaatteusz/bezpieczna-polska

Repozytorium jest puste. Zalogowana przeglądarka ma dostęp do konta; konektor
GitHub nie udostępnia repozytoriów i zwraca 404 dla tego repozytorium.
Automatyczny przegląd uprawnień dwukrotnie odrzucił przesłanie
`Bezpieczna_Polska_kod.zip`, wskazując brak bezpośredniej zgody użytkownika
na konkretny plik i cel. Nie próbować alternatywnego kanału wysyłki w celu
obejścia tej blokady. Potrzebne potwierdzenie użytkownika obejmujące projekt
i prywatne repozytorium `mmaatteusz/bezpieczna-polska`.

## Lokalne sprawdzenia

- Node.js 24.19.0, kompilacja TypeScript i 28 testów backendu: PASS.
- Flutter 3.47.4, Dart 3.13.3: ponownie 14/14 testów PASS, analiza bez błędów.
- Android SDK 36, Build Tools 36.0.0 i NDK 28.2.13676358 były zainstalowane; narzędzia w `/tmp` zniknęły przy przerwaniu sesji.
- W tym środowisku Flutter wymaga `CI=true` i `TAR_OPTIONS=--no-same-owner`.
- Proces CI uzupełniono o timeout, kontrolę podpisu APK, sumę SHA-256
  i błąd przy braku pliku wynikowego.
- Kompilacja APK nieukończona: proces zniknął podczas pobierania zależności Gradle. Szczegóły w `VALIDATION.md`. Nie deklarować, że kompilacja nadal działa w tle.
- Następna próba powinna korzystać z GitHub Actions po uzyskaniu zgody na wysłanie projektu. Nie zaczynać od kolejnej instalacji całego SDK w nietrwałym środowisku.

## Zasada wydania

Kod ma numer 0.1.0-alpha.2. Nie nazywać pełnym MVP ani wersją produkcyjną.
Lista brakujących funkcji i integracji znajduje się w README.
Brak dostępu do fizycznego telefonu oraz brak testów FCM/APNs.
Nie generować ani nie publikować klucza podpisu produkcyjnego w repozytorium.
