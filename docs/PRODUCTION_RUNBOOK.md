# Alpha.16 — production runbook

Stan: repozytorium przygotowane do wdrożenia. Hosting, domena, klucze podpisu i certyfikaty Apple muszą pochodzić od właściciela. Nie ma wdrożonej usługi ani podpisanego artefaktu sklepowego.

## Konfiguracja

- `APP_ENV=production`, `NODE_ENV=production`, `TRUST_PROXY=true`, `BUILD_SHA` (pełne 40 znaków commita), `PUBLIC_BASE_URL=https://<własna domena API>`.
- `DATABASE_URL` — prywatny PostgreSQL/PostGIS 17 (URI z zakodowanymi znakami specjalnymi hasła), `PG_POOL_MAX` domyślnie 10, `ADMIN_TOKEN` co najmniej 32 losowe znaki.
- Compose: `POSTGRES_PASSWORD`, `API_DOMAIN`, `DATABASE_URL`, `ADMIN_TOKEN`, `BUILD_SHA`; `DATABASE_URL` musi kierować na kontener `database:5432/bezpieczna`.
- Opcjonalnie `PUSH_TOKEN_ENCRYPTION_KEY` (32 bajty hex/base64), `FCM_SERVICE_ACCOUNT_JSON`, komplet `APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_BUNDLE_ID`/`APNS_PRIVATE_KEY_P8`. Bez providerów push pozostaje jawnie niedostępny.
- `ENABLE_INGESTION=false` wstrzymuje harmonogram; nie usuwa ostatniej poprawnej kopii. Sekrety przekazuj przez menedżer sekretów lub plik poza repo, nigdy przez commit.

## Wdrożenie

Skieruj rzeczywistą domenę na serwer i otwórz 80/443. Caddy w `deploy/compose.https.yaml` wystawia HTTPS i nie przepuszcza `/admin/*`. Backend nasłuchuje tylko na localhost serwera oraz wewnątrz sieci Compose. Z repozytorium przy konkretnym commicie uruchom:

```sh
docker compose -f compose.yaml -f deploy/compose.https.yaml up -d --build
docker compose -f compose.yaml -f deploy/compose.https.yaml ps
curl -fsS https://<własna domena API>/health
curl -fsS https://<własna domena API>/ready
```

`migrate` kończy się przed uruchomieniem `api`; produkcyjny `server` sprawdza wersję schematu i PostGIS, a sam nie wykonuje DDL. Migracja jest idempotentna i nie usuwa danych. `/ready` ocenia bazę; `/readyz` zachowuje starszy, ostrzejszy kontrakt synchronizacji źródeł dla preview. `/v1/sources` pokazuje ostatnie powodzenie, błąd adaptera i STALE. Administracyjne `/admin/metrics` wymaga bearer `ADMIN_TOKEN` i nie jest wystawiane przez Caddy. Metryki liczą żądania, błędy 5xx i czasy na wzorzec trasy, bez współrzędnych URL. Logi JSON na stdout obejmują czas, poziom, request ID, trasę i czas wykonania; logi błędów adaptera nie zawierają sekretów.

## Backup i restore

`backup` wykonuje pierwszy backup przy starcie i następny co 24 h. `pg_dump -Fc --compress=6` zapisuje `bezpieczna-*.dump` z `*.sha256` na osobnym wolumenie `backups-data`, retencja 14 dni. Zadbaj dodatkowo o szyfrowaną kopię poza hostem: sam wolumen nie chroni przed awarią serwera. Monitoruj, czy pojawiają się nowe pliki i czy odtwarzanie nadal przechodzi.

Odzyskanie: zatrzymaj zapis do starej bazy, skopiuj plik i jego `.sha256`, utwórz **nową pustą bazę**, następnie:

```sh
RESTORE_DATABASE_URL='postgresql://<konto>@<host>/<nowa_pusta_baza>' bash backend/scripts/restore.sh /backups/bezpieczna-YYYYMMDDTHHMMSSZ.dump
```

Skrypt weryfikuje SHA-256, odmawia nadpisania niepustej bazy, odtwarza w jednej transakcji i sprawdza PostGIS. Sprawdź `source_health`, rewizje i `/ready` na nowej bazie przed przełączeniem `DATABASE_URL`. CI tworzy dwie izolowane bazy, odtwarza prawdziwy wiersz i porównuje jego zawartość.

## Rollback i rotacja

Zachowaj SHA poprzedniego obrazu/commita. Po nieudanym wdrożeniu wróć do tego commita i ponownie zbuduj `api`; migracje alpha.16 są dodatnie. Przy przyszłej niekompatybilnej migracji przywróć backup do **nowej** bazy i zmień `DATABASE_URL`, po zatrzymaniu zapisów. Rotując hasło DB lub `ADMIN_TOKEN`, uaktualnij sekrety usługi, uruchom ją ponownie i sprawdź `/ready`. Rotacja `PUSH_TOKEN_ENCRYPTION_KEY` bez migracji zaszyfrowanych tokenów wymaga ponownej rejestracji urządzeń, więc zaplanuj ją osobno.

## Wydanie mobilne

Tag `v0.1.0-alpha.16-rc.N` uruchamia pełną regresję. Ustaw GitHub variables `PRODUCTION_API_BASE_URL` (realny HTTPS) i `PRODUCTION_BACKEND_SHA` (wdrożony backend 0.1.0-alpha.16), a także secrets `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Workflow sprawdza `/health` wdrożonego backendu i dopiero wtedy buduje AAB oraz testowy release APK; sprawdza podpis i SHA-256. Bez tych danych raportuje brak artefaktu produkcyjnego. Identyfikator Android production: `pl.bezpiecznapolska`; preview: `pl.bezpiecznapolska.preview`; development: `pl.bezpiecznapolska.dev`. Nigdy nie umieszczaj keystore w repo.

iOS: Debug/Profile używa `pl.bezpiecznapolska.preview`, Release `pl.bezpiecznapolska.bezpiecznaPolska`; uruchom z właściwym `--dart-define=APP_ENV=preview|production` oraz `API_BASE_URL`. Wydanie podpisanego IPA wymaga macOS, Apple Developer, certyfikatów i provisioning profile. CI Linux testuje wspólny kod Dart, nie podpisuje IPA.

## Diagnostyka

Sprawdź `/health` (wersja/SHA), `/ready` (baza/PostGIS), `/v1/sources` (źródła), logi `docker compose logs api migrate backup gateway` oraz wolne miejsce wolumenów. Brak świeżego źródła jest stanem STALE, nie zielonym potwierdzeniem bezpieczeństwa. 503 `/ready` oznacza bazę lub PostGIS; błędy źródeł przy 200 `/ready` diagnozuj oddzielnie. Sprawdź, czy gateway posiada prawdziwy certyfikat HTTPS.
