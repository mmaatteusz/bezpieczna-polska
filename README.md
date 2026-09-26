# Bezpieczna Polska

**Bezpieczna Polska** to aplikacja mobilna i backend do cywilnej świadomości sytuacyjnej dla Polski. Łączy oficjalne komunikaty i dane wielu instytucji, zachowuje źródło i historię zmian oraz pokazuje użytkownikowi najważniejsze informacje: **co się dzieje, gdzie, jak świeże są dane, jak wiarygodne jest źródło i gdzie znajdują się schronienia**.

Projekt jest w fazie **0.1.0-alpha.22**. Android jest obecnie główną platformą rozwojową. Kod produkcyjny i preview korzysta z jednego backendu HTTP, a część funkcji może działać z ostatnio zapisanych danych offline.

> **Stan po audycie 2026-09-26:** kod na `main` przechodzi aktualne workflowy CI, większość skonfigurowanych źródeł na Railway raportuje HEALTHY, ale środowisko Railway wymaga uporządkowania. Główna usługa `api` jest nadal przypięta do `stage/alpha22-android-gui-wczk`, a nie do `main`. Szczegóły: [AUDIT_2026-09-26.md](docs/AUDIT_2026-09-26.md).

## Najważniejsze funkcje

- status Polski i wybranego województwa,
- Alert Center z deduplikacją i korelacją komunikatów,
- mapa Polski z alertami, zdarzeniami, schronieniami i granicami województw,
- oddzielna mapa Ukrainy,
- live NEPTUN z odświeżaniem backendu co 5 s i publikacją pozycji zgrubnych,
- schronienia PSP/dane.gov.pl, wyszukiwanie w obszarze mapy i najbliższe schronienie,
- jednorazowe `Wokół mnie` z GPS uruchamianym przez użytkownika,
- obserwowane lokalizacje,
- stopnie alarmowe RP,
- dane PAA, IMGW, CERT Polska, Straży Granicznej, Policji i PSP,
- historia rewizji zdarzeń i incydentów,
- pakiety danych offline dla regionu,
- obsługa push w backendzie i aplikacji; prawdziwa wysyłka wymaga konfiguracji providerów.

## Architektura

```text
Flutter Android/iOS
        |
        | HTTPS JSON / GeoJSON
        v
Fastify / Node.js 24
        |
        +-- adaptery źródeł
        +-- korelacja / deduplikacja
        +-- source health
        +-- historia rewizji
        +-- push outbox
        |
        v
PostgreSQL + PostGIS 17
```

Backend działa jako pojedyncza usługa API z workerami ingestion uruchamianymi w procesie aplikacji. Zwykłe źródła są sprawdzane cyklicznie, a NEPTUN ma osobny worker 5-sekundowy. Dostęp do równoległych workerów jest chroniony lease w bazie.

## Źródła i moduły

| Moduł | Implementacja | Stan wg audytu Railway 2026-09-26 |
|---|---|---|
| RCB | oficjalne komunikaty i artykuły | HEALTHY |
| RSO | pełny publiczny eksport XML | HEALTHY |
| WCZK | RSO dla 16 województw + bezpośredni mirror Podkarpackiego | WCZK-18 HEALTHY; pozostałe przez RSO |
| Stopnie alarmowe RP | RCB / gov.pl | HEALTHY |
| IMGW meteo | oficjalne API | HEALTHY |
| IMGW hydro | oficjalne API | HEALTHY |
| PAA | komunikaty PAA | HEALTHY |
| PAA measurements | brak stabilnego zweryfikowanego kontraktu | wyłączone |
| CERT Polska | oficjalny RSS | HEALTHY |
| CSIRT GOV | brak publicznego feedu użytecznego dla aplikacji | NOT_CONFIGURED |
| Straż Graniczna | oficjalne aktualności, filtr operacyjny | HEALTHY |
| Policja | oficjalny RSS, filtr zdarzeń | HEALTHY |
| PSP incidents | centralne aktualności KG PSP, filtr zdarzeń | HEALTHY |
| Schronienia | PSP / dane.gov.pl + PostGIS | HEALTHY |
| UkraineAlarm | oficjalne API v3 | NOT_CONFIGURED na Railway — brak klucza |
| NEPTUN | publiczny live feed | HEALTHY |
| Push | FCM/APNs + outbox | kod gotowy; providery nie są skonfigurowane na Railway |

**Ważne:** stan HEALTHY oznacza, że adapter poprawnie wykonał ostatni cykl synchronizacji. Nie oznacza, że dane danego źródła są kompletne dla wszystkich rodzajów zdarzeń.

## Railway — aktualny stan

Projekt Railway: **Bezpieczna Polska**.

Główne elementy:

- `api` — publiczne API: `api-production-b6560.up.railway.app`,
- `PostGIS 17` — baza używana przez `DATABASE_URL`,
- `PostGIS 17-x_Uh` — osierocona druga baza, nieużywana przez `api`,
- `api-alpha20-smoke` — historyczny serwis smoke,
- `alpha20-runtime-probe` — historyczny one-shot probe.

### Znany drift wdrożenia

Na dzień audytu:

- `main`: `659d90335f62e72a9c5548d06c9dd86cc9715768`,
- Railway `api`: branch `stage/alpha22-android-gui-wczk`,
- deployment Railway: `83ed7b28d737f4c7c2ea72f6f0de76827345d299`.

To oznacza, że **Railway nie śledzi obecnie `main`**. Nowe poprawki scalone do `main` nie muszą pojawić się na backendzie, dopóki konfiguracja źródła usługi nie zostanie poprawiona i backend nie zostanie ponownie wdrożony.

## API

Najważniejsze endpointy:

```text
GET  /health
GET  /ready
GET  /status?regionId=04
GET  /v1/snapshot?regionId=04
GET  /v1/sources
GET  /v1/map/layers
GET  /v1/layers/events.geojson
GET  /v1/shelters
GET  /v1/map/shelters
POST /v1/shelters/nearest
POST /v1/around
GET  /v1/radiation
GET  /v1/ukraine
GET  /v1/neptun
GET  /v1/layers/neptun.geojson
GET  /v1/events/:id/timeline
GET  /v1/incidents/:id/timeline
GET  /v1/incidents/:id/history
```

Endpointy administracyjne wymagają `ADMIN_TOKEN` i są rate-limitowane.

## Android

Aplikacja Flutter ma cztery główne sekcje:

- Sytuacja teraz,
- Alerty,
- Mapa,
- Więcej.

Preview używa osobnego identyfikatora pakietu `pl.bezpiecznapolska.preview`. Produkcja używa `pl.bezpiecznapolska`.

Aktualny preview APK jest budowany jako **arm64-v8a only**. Do budowy wymagany jest JDK 21.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
```

Build preview:

```sh
API_BASE_URL=https://api-production-b6560.up.railway.app bash scripts/build-android.sh
```

## Backend

Wymagany Node.js 24.

```sh
cd backend
npm ci
npm run build
npm test
npm start
```

Produkcja wymaga PostgreSQL z PostGIS. SQLite jest przeznaczony tylko do testów i lokalnego developmentu.

## CI

Dla aktualnego `main` po commicie `659d9033...` zakończyły się sukcesem:

- Production infrastructure and release gate,
- Verify iOS native build,
- Build preview APK and offline regression,
- Verify PSP shelter stage,
- Verify RCB stage.

CI testuje backend, Fluttera, PostGIS i część kontraktów live. Należy jednak pamiętać, że część live-checków źródeł jest celowo nieblokująca; zielony CI nie jest równoważny z potwierdzeniem, że każdy zewnętrzny serwis działa w danej chwili.

## Offline

Pakiety offline przechowują dane bezpieczeństwa, zdarzenia i dane schronień dla regionu. Nie zawierają pełnego podkładu mapowego offline.

Brak internetu nie może być interpretowany jako brak zagrożeń. Interfejs powinien jasno odróżniać:

- dane aktualne,
- dane zapisane lokalnie,
- dane STALE,
- brak danych.

## Bezpieczeństwo i prywatność

- GPS jest używany na żądanie użytkownika.
- Precyzyjne współrzędne dla `around` i nearest shelter są przesyłane w body POST, nie w URL.
- Tokeny push są szyfrowane po stronie backendu.
- Sekrety nie powinny trafiać do repozytorium.
- Produkcja ma HSTS, nagłówki bezpieczeństwa i rate limiting.
- Brak danych ze źródła nie jest interpretowany jako brak zagrożenia.

## Co jest dobre

Projekt ma rozbudowane testy kontraktów, wyraźny model source health, fail-closed przy zmianach kontraktów, PostGIS dla operacji przestrzennych, historię rewizji, rozdzielenie danych Polski/Ukrainy oraz rozsądne ograniczenie precyzji NEPTUN. Frontend jest podzielony na osobne ekrany zamiast jednego dużego pliku i ma testy regresyjne dla map, alertów, źródeł, offline, push i NEPTUN.

## Co wymaga poprawy

Najważniejsze zadania po audycie:

1. przepiąć Railway `api` z `stage/alpha22-android-gui-wczk` na `main` i wdrażać tylko zweryfikowany HEAD,
2. zsynchronizować `BUILD_SHA` z realnym deploymentem,
3. usunąć lub zarchiwizować osierocone `PostGIS 17-x_Uh`, `api-alpha20-smoke` i `alpha20-runtime-probe`,
4. zaktualizować runtime audit, który nadal zawiera historyczne oczekiwania alpha.21 / stare SHA,
5. skonfigurować UkraineAlarm albo jawnie pozostawić ten moduł wyłączony,
6. skonfigurować FCM/APNs przed uznaniem push za działający produkcyjnie,
7. dodać pełniejszy test runtime wszystkich krytycznych źródeł jako blokujący release, a nie tylko informacyjny,
8. utrzymać monitoring świeżości schronień i zewnętrznych feedów,
9. dokończyć politykę prywatności, release signing i proces dystrybucji Androida.

## Dokumentacja

- [Audyt 2026-09-26](docs/AUDIT_2026-09-26.md)
- [Architektura](docs/ARCHITECTURE.md)
- [Źródła](docs/SOURCES.md)
- [Runbook produkcyjny](docs/PRODUCTION_RUNBOOK.md)
- [Walidacja](docs/VALIDATION.md)
- [WCZK / RSO — ponowna weryfikacja](docs/WCZK_REVERIFY_2026-09-25.md)
- [Roadmap](docs/ROADMAP.md)

## Status projektu

**Alpha.22 — aktywnie rozwijany.** Kod `main` jest w znacznie lepszym stanie niż sugerował stary README, ale przed publicznym wydaniem należy usunąć drift Railway i potwierdzić działanie funkcji zależnych od sekretów/providerów.

Nigdy nie commituj sekretów, tokenów, keystore, kluczy API ani danych użytkowników.
