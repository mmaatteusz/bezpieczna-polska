# Bezpieczna Polska

<p align="center">
  <img src="mobile/assets/brand/bezpieczna_polska_logo_transparent.png" width="360" alt="Logo Bezpieczna Polska">
</p>

**Bezpieczna Polska** to aplikacja Flutter + backend do cywilnej świadomości sytuacyjnej w Polsce. Łączy oficjalne komunikaty, dane przestrzenne i wybrane źródła informacyjne, zachowując źródło, świeżość, historię zmian i jawne ograniczenia pokrycia.

> **Status: aktywna alpha / kandydat do zamkniętej bety Android.** Android jest główną platformą. Backend produkcyjny działa na Railway i śledzi `main`. Kod może działać z ostatnią poprawną kopią danych offline, ale brak danych nigdy nie jest traktowany jako potwierdzenie bezpieczeństwa.


## Wersja i wydania

Aktualny kod rozwojowy: **0.1.0-alpha.24** (`build 25`).

Najnowsze publiczne APK Android: [v0.1.0-alpha.23](https://github.com/mmaatteusz/bezpieczna-polska/releases/latest).

Wersjonowanie alpha jest zsynchronizowane pomiędzy backendem i aplikacją mobilną. Po zmianie kodu trafiającej na `main` automatyzacja podbija numer `alpha.N` oraz numer buildu, o ile dany push nie zawiera już jawnej zmiany wersji. Dzięki temu ręczny bump nie jest podbijany drugi raz.

Automatyczny bump wersji **nie publikuje Release**. GitHub Release powstaje dopiero z przetestowanego, podpisanego APK po przejściu wymaganych kontroli CI. Ostatni opublikowany Release może więc celowo mieć niższy numer niż bieżący kod na `main`.

## Co działa

### Android

- 4 główne sekcje: **Start / Mapa / Alerty / Więcej**,
- status Polski i wybranej okolicy,
- Alert Center z filtrami, wyszukiwaniem i deduplikacją,
- mapa Polski z granicami województw, zdarzeniami i schronieniami,
- schronienia PSP/dane.gov.pl, nearest shelter i wyszukiwanie,
- `Wokół mnie` oraz obserwowane lokalizacje,
- tryb offline / LAST KNOWN GOOD dla danych bezpieczeństwa,
- NEPTUN jako osobny moduł informacyjny,
- diagnostyka źródeł,
- opt-in UI dla powiadomień,
- `Jestem bezpieczny` przez systemowy Share Sheet.

### Backend

- Fastify / Node.js 24,
- PostgreSQL + PostGIS 17,
- migracje produkcyjne,
- source health: `HEALTHY / STALE / BROKEN / NOT_CONFIGURED`,
- historia rewizji zdarzeń i incydentów,
- korelacja i deduplikacja,
- worker lease dla równoległych procesów,
- runtime `/health` i `/ready`,
- runtime audit po deploymentach Railway,
- admin API chronione bearer tokenem i rate limitingiem.

## Źródła

| Moduł | Stan |
|---|---|
| RCB | ✅ live |
| RSO / komunikaty WCZK | ✅ live |
| WCZK Podkarpackie direct mirror | ✅ live |
| Stopnie alarmowe RP | ✅ backend live; dedykowany panel Flutter istnieje, ale nie jest jeszcze wystawiony w głównej nawigacji |
| IMGW meteo | ✅ live |
| IMGW hydro | ✅ live |
| PAA — komunikaty | ✅ live |
| PAA — pomiary stacji | ✅ live; oficjalny WFS/GeoJSON, osobna warstwa informacyjna; pomiary nie tworzą alarmu |
| CERT Polska | ✅ live |
| CSIRT GOV | ⛔ brak użytecznego bieżącego publicznego feedu |
| Straż Graniczna | ✅ oficjalne publikacje z konserwatywnym filtrem operacyjnym |
| Policja | ✅ oficjalny RSS z filtrem istotnych zdarzeń |
| PSP incidents | ✅ oficjalne publikacje z filtrem istotnych zdarzeń |
| Schronienia | ✅ PostGIS + mapa + offline |
| NEPTUN | ✅ live, z publikacją zgrubnej pozycji |
| UkraineAlarm | ⛔ adapter zachowany, ale źródło jest jawnie wyłączone do czasu klucza API i uruchomienia kontrolowanego workera |
| Push | 🟡 backend + UI + outbox istnieją; realne wysyłki wymagają konfiguracji FCM/APNs |

Stan `HEALTHY` potwierdza poprawny ostatni cykl synchronizacji adaptera. Nie oznacza kompletności wszystkich zdarzeń w kraju.

### Kontrakt jakości źródeł

Każde źródło deklaruje dwie niezależne cechy:

- `sourceClass`: `STATUS`, `CONTEXT`, `REFERENCE` albo `SITUATIONAL`,
- `absenceSemantics`: `AUTHORITATIVE_EMPTY_SET` albo `NOT_PROVABLE`.

Wzorzec stanowią bieżące API IMGW: poprawnie pobrany pusty zestaw jest tam wiarygodną informacją o braku aktywnych ostrzeżeń danego typu. RCB, RSO, WCZK, PAA-komunikaty i inne listy publikacji nie dostają takiego statusu tylko dlatego, że synchronizacja się udała. Źródła kontekstowe i referencyjne nie blokują głównego statusu kraju, ale nadal są widoczne w diagnostyce i mogą dostarczać zdarzenia lub dane pomocnicze.

## Railway

Główna usługa:

```text
api
https://api-production-b6560.up.railway.app
source: mmaatteusz/bezpieczna-polska
branch: main
root: /backend
healthcheck: /ready
```

Zmiany w `backend/**` na `main` uruchamiają deployment Railway. Zmiany tylko mobilne są poprawnie pomijane przez backendowy deploy.

Aktywna baza produkcyjna: **PostGIS 17**.

Do usunięcia z Railway po weryfikacji backupu pozostają historyczne zasoby:

- `PostGIS 17-x_Uh`,
- `api-alpha20-smoke`,
- `alpha20-runtime-probe`.

## Android signing i aktualizacje

Rozdzielone są trzy linie instalacyjne:

```text
development: pl.bezpiecznapolska.dev
preview:     pl.bezpiecznapolska.preview
production:  pl.bezpiecznapolska
```

Preview korzysta ze stałego signera i monotonicznego `versionCode`.

CI wykonuje prawdziwy test Android PackageManager:

1. instaluje starsze APK,
2. zapisuje dane aplikacji,
3. wykonuje `adb install -r` nowszej wersji,
4. potwierdza zachowanie danych,
5. potwierdza odrzucenie downgrade przez `INSTALL_FAILED_VERSION_DOWNGRADE`.

Produkcja ma osobny release gate i osobny finalny keystore właściciela. Prywatnego keystore nie wolno commitować.

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

## Budowanie

Backend:

```sh
cd backend
npm ci
npm run build
npm test
npm start
```

Flutter:

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
```

Lokalny build Androida domyślnie używa pakietu developerskiego. Dystrybuowalny preview należy budować przez GitHub Actions, żeby zachować prawidłowy signer i linię `versionCode`. Publiczne APK alpha są publikowane w GitHub Releases dopiero po zielonym buildzie.

## Co zostało do wydania produkcyjnego

Najważniejsze otwarte elementy:

1. wygenerować i bezpiecznie zarchiwizować finalny production keystore,
2. wykonać pierwszy podpisany production AAB/APK,
3. skonfigurować FCM przed reklamowaniem push jako działającego,
4. podpiąć gotowy panel stopni alarmowych do UI,
5. dopracować prezentację świeżości pomiarów PAA per stacja i komunikaty o danych nieaktualnych,
6. UkraineAlarm uruchomić dopiero po uzyskaniu i zweryfikowaniu klucza API,
7. przygotować politykę prywatności i Google Play Data Safety,
8. wykonać pierwszy Google Play Internal Test,
9. posprzątać historyczne zasoby Railway,
10. później: panel administratora + MFA, pełny basemap offline i iOS release.

## Dokumentacja

Aktualne dokumenty:

- [Roadmap](docs/ROADMAP.md)
- [Audyt / stan projektu](docs/AUDIT_2026-09-26.md)
- [Architektura](docs/ARCHITECTURE.md)
- [Źródła](docs/SOURCES.md)
- [Runbook produkcyjny](docs/PRODUCTION_RUNBOOK.md)
- [Walidacja i CI](docs/VALIDATION.md)

Dokumenty etapów integracji pozostają w `docs/` jako historia decyzji technicznych i źródeł, ale nie są źródłem bieżącego statusu projektu.

## Zasady projektu

- brak danych ≠ bezpieczeństwo,
- źródła oficjalne, agregatory i OSINT mają odrębną tożsamość,
- nie zgadujemy geometrii ani kompletności źródeł,
- STALE jest widoczne użytkownikowi,
- stopnie alarmowe nie oznaczają automatycznie bezpośredniego zagrożenia,
- NEPTUN nie zastępuje oficjalnych alarmów,
- sekrety, tokeny, keystore i dane użytkowników nie trafiają do repozytorium.
