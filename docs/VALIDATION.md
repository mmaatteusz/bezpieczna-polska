# Walidacja i CI

Ten dokument opisuje bieżącą strategię walidacji. Historyczne zrzuty pojedynczych przebiegów testów nie są źródłem prawdy; aktualny stan należy odczytywać z GitHub Actions i runtime auditu Railway.

## Backend

Wymagane dla zmian backendu:

- Node.js 24,
- TypeScript build,
- pełne testy backendu,
- PostgreSQL + PostGIS,
- migracje produkcyjne,
- test idempotencji migracji,
- persistence/restart,
- backup/restore smoke,
- security audit zależności.

## Flutter

Wymagane dla zmian mobilnych:

- `flutter pub get`,
- format check,
- `flutter analyze`,
- `flutter test`,
- testy kontraktów offline,
- testy map, alertów, źródeł, push i NEPTUN.

## Android preview

Dystrybuowalny preview:

- package: `pl.bezpiecznapolska.preview`,
- stały preview signer,
- monotoniczny CI `versionCode`,
- arm64 preview APK,
- automatyczna kontrola package/version/signature.

Lokalne debug buildy używają `pl.bezpiecznapolska.dev`, aby przypadkowy debug keystore nie zrywał linii aktualizacji preview.

## Android update-in-place

Workflow `Verify Android in-place APK update` uruchamia emulator i sprawdza Android PackageManager:

1. buduje starszy preview APK,
2. buduje nowszy preview APK z wyższym `versionCode`,
3. instaluje starszą wersję,
4. zapisuje dane aplikacji,
5. wykonuje `adb install -r` nowszej wersji,
6. potwierdza zachowanie danych,
7. potwierdza odrzucenie próby downgrade.

Test ma wykrywać zmianę signera, błędny package id i regresję numeracji wersji przed wydaniem APK.

## Production release

Release gate sprawdza m.in.:

- backend i PostGIS,
- spójność wersji,
- produkcyjny backend,
- wymagane sekrety,
- finalny Android signer,
- przypięty SHA-256 certyfikatu,
- podpis AAB/APK,
- package id `pl.bezpiecznapolska`,
- poprawny `versionCode`.

Job `android-release` nie uruchamia się przy każdym pushu do `main`. Jest przeznaczony dla release tag/manualnego uruchomienia i dlatego zwykły push może pokazywać go jako `Skipped`.

## Runtime Railway

`.github/workflows/audit-production-runtime.yml` sprawdza faktycznie wdrożony backend.

Test obejmuje:

- `/health`,
- `/ready`,
- source health,
- snapshot,
- status,
- map layers,
- schronienia,
- nearest shelter,
- `/v1/around`,
- PAA,
- Ukraine endpoint,
- NEPTUN i jego GeoJSON,
- postęp workera NEPTUN.

Audit oczekuje dokładnego wdrożonego SHA przy deployowalnych zmianach backendu. Nie używa historycznego hardcoded commita.

## Zewnętrzne źródła

Zielony test kodu nie gwarantuje, że każda zewnętrzna instytucja jest dostępna w każdej sekundzie.

Zasady:

- zmiana kontraktu źródła ma powodować fail-closed,
- ostatnia poprawna kopia jest zachowywana,
- STALE/BROKEN są jawne,
- źródło częściowe nie staje się automatycznie kompletnym,
- brak danych nie oznacza bezpieczeństwa.

Szczegóły kontraktów znajdują się w [SOURCES.md](SOURCES.md) i dokumentach etapów integracji.
