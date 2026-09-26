# Production runbook — Bezpieczna Polska

Aktualny kod: **0.1.0-alpha.22**.

Ten dokument opisuje docelowy sposób wdrożenia. Stan faktycznego Railway z 2026-09-26 jest opisany w [AUDIT_2026-09-26.md](AUDIT_2026-09-26.md).

## Wymagane zmienne backendu

W production wymagane są co najmniej:

- `APP_ENV=production`,
- `NODE_ENV=production`,
- `TRUST_PROXY=true`,
- `BUILD_SHA=<pełny 40-znakowy SHA wdrożonego commita>`,
- `PUBLIC_BASE_URL=https://<publiczny-host-api>`,
- `DATABASE_URL=<PostgreSQL/PostGIS 17>`,
- `ADMIN_TOKEN=<min. 32 losowe znaki>`.

Opcjonalne moduły:

- `UKRAINE_ALARM_API_KEY` — oficjalny live UkraineAlarm,
- `PUSH_TOKEN_ENCRYPTION_KEY` — wymagany do uruchomienia PushService,
- `FCM_SERVICE_ACCOUNT_JSON` — Android push,
- `APNS_KEY_ID`,
- `APNS_TEAM_ID`,
- `APNS_BUNDLE_ID`,
- `APNS_PRIVATE_KEY_P8` — iOS push.

`ENABLE_INGESTION=false` wyłącza cykliczną synchronizację, ale nie usuwa ostatnich danych.

## Railway — zasada wdrożenia

Produkcja powinna korzystać z jednego źródła prawdy:

```text
GitHub main -> Railway api -> production PostGIS
```

Nie należy utrzymywać produkcyjnego API przypiętego do brancha etapowego po zakończeniu danego etapu.

Po każdym wdrożeniu sprawdź:

```text
Railway source branch == main
deployment commit == BUILD_SHA
deployment commit == oczekiwany GitHub main HEAD
```

Jeżeli którykolwiek z tych warunków nie jest spełniony, deployment jest niespójny.

## Aktualny Railway podczas audytu 2026-09-26

Główna usługa:

```text
api
https://api-production-b6560.up.railway.app
```

Aktywna baza:

```text
PostGIS 17
service id: 9e760220-ba2e-4cea-b2b4-3fb4403a5102
```

Znany problem:

```text
api source branch: stage/alpha22-android-gui-wczk
main: 659d90335f62e72a9c5548d06c9dd86cc9715768
deployed commit: 83ed7b28d737f4c7c2ea72f6f0de76827345d299
```

Przed uznaniem Railway za poprawnie zsynchronizowany produkcyjnie należy przepiąć usługę na `main` i wykonać kontrolowany redeploy.

## Migracje

Railway `api` ma pre-deploy command:

```sh
node dist/migrate.js
```

Po migracji backend uruchamia `/ready`, które sprawdza bazę i PostGIS.

Migracje muszą pozostać idempotentne. Przy zmianach destrukcyjnych najpierw wykonaj backup i odtwórz go na nowej bazie testowej.

## Healthcheck

Podstawowy zestaw:

```sh
curl -fsS https://<api>/health
curl -fsS https://<api>/ready
curl -fsS https://<api>/v1/sources
curl -fsS "https://<api>/v1/snapshot?regionId=04"
curl -fsS https://<api>/v1/neptun
```

Interpretacja:

- `/health` — wersja i SHA,
- `/ready` — baza, migracje, PostGIS,
- `/v1/sources` — świeżość i błędy źródeł,
- `/v1/snapshot` — kontrakt aplikacji,
- `/v1/neptun` — stan osobnego workera NEPTUN.

`/ready=200` nie oznacza, że wszystkie źródła zewnętrzne są HEALTHY.

## Minimalny runtime gate przed wydaniem APK

Release powinien zostać zablokowany, jeżeli:

1. `/health.version` nie odpowiada oczekiwanej wersji,
2. `/health.buildSha` nie odpowiada wdrożonemu SHA,
3. `/ready` nie zwraca PostGIS,
4. RCB jest BROKEN/STALE ponad dopuszczalne okno,
5. wymagany moduł mapy nie działa,
6. NEPTUN jest wymagany w danym release, ale nie przechodzi live contractu,
7. schronienia nie mają żadnej poprawnej kopii,
8. backend odpowiada z innego deploymentu niż zadeklarowany.

Moduły opcjonalne muszą być jawnie oznaczone jako NOT_CONFIGURED, a nie udawać HEALTHY.

## Backup

Backup musi obejmować aktywną bazę wskazaną przez `DATABASE_URL`.

Przed usunięciem dodatkowej/uszkodzonej instancji PostGIS wykonaj backup i upewnij się, że nie zawiera jedynej kopii danych.

Przykład restore:

```sh
RESTORE_DATABASE_URL='postgresql://<konto>@<host>/<pusta_baza>' \
  bash backend/scripts/restore.sh /backups/bezpieczna-YYYYMMDDTHHMMSSZ.dump
```

Po restore:

- sprawdź PostGIS,
- sprawdź `source_health`,
- sprawdź rewizje,
- uruchom `/ready`,
- wykonaj runtime smoke.

## Rollback

Rollback powinien wskazywać konkretny commit/obraz, a `BUILD_SHA` musi zostać ustawiony na faktycznie uruchamianą wersję.

Nie wykonuj rollbacku przez samo przepięcie zmiennej SHA bez zmiany kodu deploymentu.

## Android release

Android ma dwa rozdzielone łańcuchy instalacji:

```text
preview:    pl.bezpiecznapolska.preview
production: pl.bezpiecznapolska
```

Nie są to wzajemne aktualizacje. Preview aktualizuje wyłącznie preview, a produkcja wyłącznie produkcję. Dzięki osobnym `applicationId` mogą być zainstalowane równolegle.

### Preview signing i update-in-place

Preview ma jeden stały certyfikat podpisujący. CI odmawia zbudowania pakietu `.preview`, jeżeli permanentny signer nie jest dostępny lub jego SHA-256 nie odpowiada przypiętemu fingerprintowi. Zwykły lokalny debug używa `pl.bezpiecznapolska.dev`, więc nie może przypadkiem zatruć łańcucha aktualizacji preview innym kluczem.

Każdy dystrybuowany preview APK dostaje CI-owy, rosnący w czasie bazowy `versionCode`. Dla arm64 split Flutter dodaje offset ABI. Nie należy ręcznie zastępować tego numeru numerem z `pubspec.yaml` w workflowach preview.

Workflow `Verify Android in-place APK update` wykonuje prawdziwy test PackageManagera na emulatorze:

1. buduje dwie APK z tym samym signerem i rosnącym `versionCode`,
2. instaluje starszą,
3. zapisuje dane w prywatnym katalogu aplikacji,
4. wykonuje `adb install -r` nowszej APK bez deinstalacji,
5. potwierdza nowy `versionCode` i zachowanie danych,
6. potwierdza, że downgrade do starszego APK jest odrzucony.

`scripts/setup-preview-signing.ps1` nie generuje już zastępczego klucza. Służy wyłącznie do ponownego wgrania sekretów z prywatnego backupu istniejącego signera. Utrata tego backupu nie może być „naprawiana” przez wygenerowanie nowego klucza bez świadomej rotacji i zerwania zgodności aktualizacji.

### Finalny production keystore

Przed pierwszym rozpowszechnieniem `pl.bezpiecznapolska` utwórz finalną tożsamość podpisującą na zaufanym komputerze:

```powershell
.\scripts\setup-production-signing.ps1
```

Skrypt tworzy lub ponownie wykorzystuje prywatny backup w `~/.bezpieczna-polska/production-signing`, ustawia sekrety GitHub oraz zapisuje publiczny fingerprint jako `PRODUCTION_SIGNING_CERT_SHA256`. Backup keystore i pliku credentiali musi istnieć w co najmniej dwóch niezależnych, zaszyfrowanych lokalizacjach.

Build production wymaga:

- poprawnego `PRODUCTION_API_BASE_URL`,
- oczekiwanego `PRODUCTION_BACKEND_SHA`,
- `ANDROID_KEYSTORE_B64`,
- `ANDROID_KEYSTORE_PASSWORD`,
- `ANDROID_KEY_ALIAS`,
- `ANDROID_KEY_PASSWORD`,
- `PRODUCTION_SIGNING_CERT_SHA256`.

Release gate przed budową porównuje faktyczny certyfikat z przypiętym SHA-256. APK podpisana innym poprawnym kluczem jest traktowana jako błąd, ponieważ zerwałaby możliwość aktualizacji istniejącej instalacji.

Dla release tagów workflow dodatkowo wymaga, aby build number z `mobile/pubspec.yaml` był większy od maksymalnego build number wcześniejszych tagów. Chroni to zarówno bezpośrednie APK, jak i AAB przed przypadkowym cofnięciem `versionCode`.

Po buildzie sprawdź:

- package id,
- versionName,
- versionCode,
- fingerprint podpisu,
- SHA-256 pliku,
- instalację aktualizacji na istniejącej poprzedniej wersji.

## Push

Push jest produkcyjnie gotowy dopiero, gdy:

- istnieje `PUSH_TOKEN_ENCRYPTION_KEY`,
- FCM/APNs provider jest skonfigurowany,
- aplikacja uzyskuje token,
- rejestracja urządzenia działa,
- outbox przechodzi z PENDING/RETRY do DELIVERED w realnym teście.

Sam zielony test jednostkowy nie oznacza działającego push.

## UkraineAlarm

Brak `UKRAINE_ALARM_API_KEY` oznacza oczekiwane `NOT_CONFIGURED`.

Nie należy prezentować modułu jako live, jeżeli klucz nie jest skonfigurowany.

## Sprzątanie Railway

Po potwierdzeniu backupów i zależności usuń lub zarchiwizuj historyczne elementy:

- `PostGIS 17-x_Uh` — podczas audytu nieużywany przez `api`,
- `api-alpha20-smoke`,
- `alpha20-runtime-probe`.

Docelowo production powinien być prosty do zrozumienia bez wiedzy o starych etapach alpha.20/21.

## Sekrety

Nigdy nie commituj:

- `.env`,
- tokenów API,
- `ADMIN_TOKEN`,
- keystore,
- kluczy Firebase/APNs,
- credentiali bazy,
- baz danych użytkowników.

Dokumentacja ma opisywać **nazwy** zmiennych, nie ich wartości.
