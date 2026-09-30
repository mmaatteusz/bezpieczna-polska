# Bezpieczna Polska

<p align="center">
  <img src="mobile/assets/brand/bezpieczna_polska_logo_transparent.png" width="320" alt="Logo Bezpieczna Polska">
</p>

**Cywilna świadomość sytuacyjna w jednym miejscu:** oficjalne komunikaty, status kraju i okolicy, mapa, schronienia, stopnie alarmowe, dane PAA, Ukraina, NEPTUN i powiadomienia.

> Bezpieczna Polska nie jest państwowym systemem alarmowym. Nie zastępuje Alert RCB, numeru 112 ani komunikatów właściwych służb. Brak wpisu w aplikacji nie oznacza braku zagrożenia.

## Status i pobieranie

Projekt jest w aktywnej fazie alpha. Android jest platformą priorytetową; publikacja w Google Play jest przygotowywana.

Aktualny kod rozwojowy: **0.1.0-alpha.63** (`build 64`).

**[Pobierz opublikowane wydania Android z GitHub Releases](https://github.com/mmaatteusz/bezpieczna-polska/releases)**

Wersja w repozytorium, wersja wdrożonego backendu i ostatnie opublikowane wydanie mogą się różnić. Automatyczne podbicie wersji na `main` nie publikuje APK ani nie potwierdza wdrożenia Oracle. Tożsamość uruchomionego API pokazuje `/health`.

| Plik / kanał | Przeznaczenie |
|---|---|
| Preview APK ARM64 | Instalacja i testy na telefonie Android; osobny pakiet preview |
| Produkcyjny APK ARM64 | Instalacja podpisanej aplikacji produkcyjnej |
| Produkcyjny AAB | Wysyłka do Google Play; nie instaluje się go bezpośrednio jak APK |
| SHA256SUMS.txt | Kontrola integralności plików danego wydania |

Pakiet produkcyjny instaluje się oddzielnie od preview. GitHub Release i publikacja w Google Play to odrębne operacje. Dostępne pliki oraz status konkretnego wydania są opisane w jego release notes.

## Co oferuje aplikacja

- **Start:** status Polski i wybranego województwa, stopnie alarmowe, komunikaty oraz widoczna świeżość danych.
- **Centrum alertów:** komunikaty z monitorowanych źródeł, deduplikacja i historia.
- **Mapa:** przełączane warstwy zdarzeń, schronień, promieniowania oraz danych sytuacyjnych; szczegóły po wybraniu obiektu.
- **Schronienia:** wyszukiwanie, mapa, najbliższe obiekty i dane zapisane offline. Wpis w bazie nie gwarantuje dostępności, otwarcia ani bezpieczeństwa obiektu.
- **PAA:** pomiary i komunikaty dotyczące promieniowania z informacją o źródle i czasie.
- **Ukraina:** oficjalny UkraineAlarm API v3 jako warstwa sytuacyjna; alarmy Ukrainy nie zmieniają statusu Polski.
- **NEPTUN:** publiczne dane sytuacyjne, czas serwera i odświeżanie. Przybliżone położenie nie daje podstaw do wyliczania toru, prędkości czy trasy.
- **GPSJAM:** dzienne dane o dokładności pozycji samolotów; nie stanowią samodzielnego dowodu zagłuszania.
- **Obserwowane miejsca i powiadomienia:** wybór kategorii i lokalizacji, rejestracja urządzenia, rzeczywisty test push.
- **Offline:** ostatnia poprawna kopia danych i widoczne oznaczenie ich wieku.

## Źródła i interpretacja danych

Backend integruje m.in. RCB, RSO, stopnie alarmowe, IMGW METEO/HYDRO, PAA, schronienia, komunikaty wojewódzkie i służb, UkraineAlarm oraz NEPTUN. Bieżący stan każdej integracji jest dostępny pod [`/v1/sources`](https://bezpieczna-polska-api.duckdns.org/v1/sources).

Stan `HEALTHY` opisuje poprawność i świeżość integracji, a nie pełną wiedzę o sytuacji. Źródła mają klasy `STATUS`, `CONTEXT`, `REFERENCE` i `SITUATIONAL`. Brak danych może oznaczać `AUTHORITATIVE_EMPTY_SET` lub `NOT_PROVABLE`; tych sytuacji nie wolno utożsamiać. Przy błędzie synchronizacji aplikacja może zachować ostatnią poprawną kopię z oznaczeniem degradacji lub nieaktualności.

### Ostatni potwierdzony audyt migracji

Podczas audytu 30.09–01.10.2026 uzyskano `ORACLE_HOST_AUDIT_PASS` i `PROBE_ALL_OK`. Smoke test potwierdził kontrakty krytycznych źródeł RCB, RSO, LEVELS, SHELTERS, IMGW METEO/HYDRO, PAA, UA i NEPTUN, odpowiedzi API mapy i schronień oraz odświeżenie NEPTUN.

Znane ograniczenia z tego audytu:

| Źródło | Stan | Szczegóły |
|---|---|---|
| SHELTERS | DEGRADED | `SHELTER_FALLBACK_OLDER_THAN_LAST_GOOD`; zachowano 86 388 obiektów, data źródłowa 21.09.2026 |
| WCZK-18 | BROKEN | `WCZK_HTML_CONTRACT_CHANGED`; adapter wymaga dostosowania |

Przejście smoke testu uwzględnia dopuszczoną ostatnią poprawną kopię schronień. Nie oznacza, że wszystkie źródła są zdrowe. Powyższe wyniki są zapisem audytu, a nie obietnicą bieżącej dostępności.

## Backend na Oracle Cloud

Docelowy adres nowych buildów Android:

**https://bezpieczna-polska-api.duckdns.org**

| Element | Konfiguracja |
|---|---|
| Region | OCI Frankfurt |
| Host | Ubuntu 24.04 ARM64, VM.Standard.A1.Flex |
| Zasoby | 1 OCPU, 6 GB RAM, boot volume około 100 GB |
| API | Node.js 24, TypeScript, Fastify, Docker |
| Reverse proxy | nginx i HTTPS z automatycznym odnowieniem certyfikatu |
| Baza | PostgreSQL 17 i PostGIS 3.6 |
| Publiczne porty | 80 i 443; SSH 22 ograniczany administracyjnie w OCI |
| Prywatne porty | PostgreSQL 5432 i API 8080 nie są otwarte publicznie |

PostgreSQL nasłuchuje na localhost. Aplikacja korzysta z roli `bp_app` bez uprawnień superuser. nginx obsługuje HTTPS i przekazuje ruch do prywatnego API. Sekrety hosta są przechowywane poza repozytorium z ograniczonymi uprawnieniami.

Migracja obejmuje sprawdzenie architektury, przypięcie klucza hosta SSH, preflight, audyt usług i sieci, odtworzenie bazy oraz testy API. Szczegóły: [Oracle cutover runbook](docs/ORACLE_CUTOVER_RUNBOOK.md).

### Railway w okresie przejściowym

Railway pozostaje uruchomiony dla okresu przejściowego i starszych buildów. Automatyczna wysyłka push została tam wyłączona; na Oracle została włączona po porównaniu rejestracji urządzeń i historii wysyłki.

Porównanie potwierdziło: brak urządzeń obecnych wyłącznie na Railway, brak nowszych rejestracji Railway, brak różnic porównanej historii push i zgodność klucza szyfrowania tokenów.

Zmiana adresu w GitHub Variables wpływa na **nowe buildy**. Nie zmienia adresu zapisanego w już zainstalowanym APK. Railway i Oracle nie mają automatycznej replikacji baz, więc Railway nie jest automatycznie aktualnym zapasowym backendem. Wyłączenie usług Railway wymaga zakończenia przejścia klientów i sprawdzenia pozostałych zależności.

## Backup i odzyskiwanie bez komputera autora

- Codzienny timer tworzy dump PostgreSQL, metadane i SHA-256.
- Hook wysyła kopię poza VM do prywatnego OCI Object Storage przez instance principals.
- Uprawnienia VM do obiektów backupu umożliwiają tworzenie i inspekcję, bez odczytu, nadpisywania i usuwania.
- Wymagany upload poza VM jest częścią powodzenia zadania backupu.
- Kopię pobraną z Object Storage sprawdzono sumą SHA-256 i odtworzono w izolowanej bazie: schema 2, 31 źródeł, 86 388 schronień.
- Zaszyfrowany pakiet konfiguracji hosta wykorzystuje Scrypt i AES-256-GCM. Pobraną kopię odszyfrowano i zweryfikowano bez wypisywania sekretów.
- Zdalną kopię klucza SSH zabezpieczono hasłem i potwierdzono logowanie.
- Zdalną kopię klucza upload Android zabezpieczono hasłem i potwierdzono poprawność keystore.

Hasła odzyskiwania muszą być dostępne w niezależnym menedżerze haseł. GitHub Secrets służą CI i nie pozwalają później pobrać ich wartości jako kopii odzyskiwania. Po zmianie konfiguracji lub wdrożenia należy odświeżyć pakiet odzyskiwania.

Testy komponentów odzyskiwania nie zastępują pełnego ćwiczenia odtworzenia nowej VM. Do dalszego dopracowania pozostają monitoring backupów, retencja oraz pełny test awarii hosta.

Instrukcje: [Backup poza VM i odzyskiwanie](docs/ORACLE_OFF_VM_BACKUP.md).

## Android i powiadomienia push

Android używa Firebase Cloud Messaging. Test wysłany przez Oracle został odebrany na rzeczywistym telefonie. Obsługa wiadomości w foreground pokazuje systemowe powiadomienie z ikoną aplikacji; wymagana jest systemowa zgoda na powiadomienia.

Komunikat „test wysłany przez serwer” oznacza przyjęcie wysyłki przez backend, nie potwierdzenie wyświetlenia na telefonie. Ustawienia systemu, oszczędzanie baterii i stan aplikacji mogą wpływać na odbiór.

Dalsze testy przed szeroką publikacją obejmują tło, zamkniętą aplikację, różne urządzenia oraz ograniczenia baterii. iOS/APNs wymaga osobnej konfiguracji i walidacji.

| Kanał | Android application ID |
|---|---|
| Development | `pl.bezpiecznapolska.dev` |
| Preview | `pl.bezpiecznapolska.preview` |
| Production | `pl.bezpiecznapolska` |

Preview ma stabilny podpis i rosnący `versionCode` w CI. Produkcja używa oddzielnego klucza upload i przypiętego SHA-256 certyfikatu. Klucze, hasła i pliki z sekretami nie trafiają do repozytorium.

Firebase ma odrębną rejestrację aplikacji produkcyjnej. Workflow produkcyjny używa `FIREBASE_PRODUCTION_ANDROID_APP_ID` z kompatybilnym fallbackiem do `FIREBASE_ANDROID_APP_ID`; preview zachowuje własną tożsamość.

## Buildy, wydania i Google Play

- [Preview APK](.github/workflows/preview-apk.yml): testy backendu i Flutter, kontrola źródeł, stabilny podpis preview i APK ARM64.
- [Production release gate](.github/workflows/production-release.yml): regresja z prawdziwym PostgreSQL/PostGIS, sprawdzenie API i wdrożonego SHA, kontrola podpisu oraz podpisany AAB i APK.
- Wydanie powinno wskazywać konkretny commit i zawierać pliki z zakończonego builda, ich SHA-256 oraz informacje o pakiecie i podpisie.
- Produkcyjny build wymaga zgodnej wersji wdrożonego API, adresu backendu, konfiguracji Firebase i klucza podpisującego.
- Publikacja GitHub Release nie oznacza dostępności w Google Play. Play wymaga osobnego przesłania AAB i zakończenia procesu w Play Console.

## API

| Metoda | Endpoint | Zastosowanie |
|---|---|---|
| GET | `/health` | Wersja, build SHA i środowisko |
| GET | `/ready` | Gotowość bazy i PostGIS |
| GET | `/v1/sources` | Stan i świeżość źródeł |
| GET | `/status?regionId=04` | Status regionu |
| GET | `/v1/snapshot?regionId=04` | Dane ekranu Start |
| GET | `/v1/map/layers` | Dostępne warstwy mapy |
| GET | `/v1/layers/events.geojson` | Zdarzenia na mapie |
| GET | `/v1/shelters`, `/v1/map/shelters` | Lista i mapa schronień |
| GET | `/v1/radiation` | Dane PAA |
| GET | `/v1/ukraine` | Oficjalne alarmy Ukrainy |
| GET | `/v1/neptun`, `/v1/layers/neptun.geojson` | Warstwa NEPTUN |
| POST | `/v1/shelters/nearest`, `/v1/around` | Dane dla wskazanej lokalizacji |

Dokładne parametry i kontrakty należy sprawdzać w kodzie backendu oraz testach.

## Uruchomienie lokalne

Wymagane są Node.js 24, Flutter zgodny z wersją CI oraz PostgreSQL/PostGIS dla testów integracyjnych.

Backend:

```bash
cd backend
npm ci
npm run build
npm test
npm start
```

Flutter:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

Uruchomienie klienta wymaga konfiguracji środowiska i adresu API. Produkcyjnego builda nie należy tworzyć z demonstracyjnym backendem ani niepełnymi ustawieniami Firebase. Instrukcje wdrożenia i zmienne środowiskowe opisuje [Production runbook](docs/PRODUCTION_RUNBOOK.md).

## Weryfikacja w CI

CI obejmuje kompilację i testy TypeScript, prawdziwy PostgreSQL/PostGIS, migracje, restart bazy, backup/restore, audyt zależności, formatowanie/analyze/testy Flutter, kontrakty push i NEPTUN oraz kontrolę tożsamości buildów Android. Testy infrastruktury Oracle sprawdzają m.in. upload backupów i integralność zaszyfrowanego pakietu odzyskiwania.

Zewnętrzne źródła mogą być niedostępne niezależnie od aplikacji. Testy rozróżniają wymagane kontrakty od diagnostyki dostępności; w runtime istotne są bezpieczna degradacja i informacja o wieku danych.

## Dalsze prace

- Podpisany build produkcyjny i publikacja GitHub Release zgodne z wdrożonym API.
- Google Play: konfiguracja konta, wymagane testy, opis sklepu, polityka prywatności i Data safety.
- Szersze testy push na Androidzie.
- Naprawa WCZK-18 i bieżącej synchronizacji schronień.
- Monitoring, retencja backupów i pełne ćwiczenie odtworzenia hosta.
- Zakończenie obsługi starszych klientów przed wyłączeniem Railway.
- Dalszy rozwój offline, mapy i osobna walidacja iOS.

## Struktura repozytorium

| Katalog | Zawartość |
|---|---|
| `backend/` | API, adaptery źródeł, baza, ingestion i push |
| `mobile/` | Aplikacja Flutter i konfiguracja Android/iOS |
| `infra/oracle/` | Bootstrap, deploy, audyt, backup i odzyskiwanie |
| `scripts/` | Kontrola wersji i buildów |
| `.github/workflows/` | CI i buildy Android |
| `docs/` | Architektura, źródła, audyty i runbooki |

## Dokumentacja

- [Roadmap](docs/ROADMAP.md)
- [Architektura](docs/ARCHITECTURE.md)
- [Źródła](docs/SOURCES.md)
- [Production runbook](docs/PRODUCTION_RUNBOOK.md)
- [Oracle cutover runbook](docs/ORACLE_CUTOVER_RUNBOOK.md)
- [Oracle access checklist](docs/ORACLE_ACCESS_CHECKLIST.md)
- [Backup poza VM i odzyskiwanie](docs/ORACLE_OFF_VM_BACKUP.md)
- [Walidacja](docs/VALIDATION.md)

Audyty z datą w nazwie dokumentu są zapisem historycznym. Stan bieżący potwierdzają runtime, najnowsze wyniki CI oraz testy konkretnego wydania.
