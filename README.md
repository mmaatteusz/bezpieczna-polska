> Alpha.12 — moduł Ukraina: oficjalne API UkraineAlarm v3, osobny status, historia/revisions, offline STALE i administracyjna warstwa MapLibre. Bieżące dane wymagają `UKRAINE_ALARM_API_KEY`; brak klucza jest jawnie NOT_CONFIGURED. [Kontrakt i ograniczenia](docs/ALPHA12_UKRAINE.md).

# Bezpieczna Polska

**Bezpieczna Polska** to cywilny system świadomości sytuacyjnej dla Polski. Łączy oficjalne komunikaty i dane służb, aby odpowiedzieć użytkownikowi: **co się dzieje, czy dotyczy Polski lub jego regionu, jak aktualna i wiarygodna jest informacja, co zrobić oraz gdzie znajduje się najbliższe schronienie**.

Aplikacja nie jest zwykłym agregatorem newsów ani mapą wojny. Zachowuje pochodzenie komunikatów, historię korekt, stan źródeł i nie interpretuje braku danych jako braku zagrożenia.

Aktualna wersja: **0.1.0-alpha.11 — wersja rozwojowa, nie pełne MVP.**

### Co działa w alpha.11

- Status Polski i status lokalny z wyjaśnieniem „Dlaczego taki status?”.
- Oficjalne źródła i integracje: RCB, RSO, WCZK, stopnie alarmowe RP, PAA, CERT Polska, Straż Graniczna, Policja i PSP.
- Katalog schronień PSP/dane.gov.pl z PostGIS, wyszukiwaniem, mapą, nearest shelter i ograniczonym cache offline.
- Alert Center, korelacja i deduplikacja zdarzeń, rewizje i historia korekt.
- **Obserwowane lokalizacje** zapisywane lokalnie na urządzeniu.
- **„Wokół mnie”** z jednorazowym GPS uruchamianym wyłącznie przez użytkownika — bez ciągłego śledzenia i bez historii ruchu.
- Odległość do zdarzenia jest liczona wyłącznie wtedy, gdy źródło dostarcza wiarygodną geometrię. Brak geometrii nie jest traktowany jako brak zdarzeń w pobliżu.
- Preview APK jest budowany jako **arm64-v8a only**.

### Najważniejsze ograniczenia

- To nadal wersja alpha, bez produkcyjnego hostingu, push, Ukrainy i modułu NEPTUN.
- PAA measurements pozostają wyłączone do czasu zweryfikowanego stabilnego publicznego kontraktu.
- CSIRT GOV pozostaje jawnie `NOT_CONFIGURED`, dopóki oficjalna lista kanałów RSS jest pusta.
- Część źródeł jest ograniczona do publikacji publicznych i nie stanowi pełnego operacyjnego rejestru zdarzeń.
- Brak nowych danych lub brak geometrii **nie oznacza bezpieczeństwa**.

## Uruchomienie

Backend wymaga Node.js 24:

```sh
cd backend
npm ci
npm run build
npm test
npm run ingest
npm start
```

API domyślnie słucha na `127.0.0.1:8080`. `GET /v1/snapshot?regionId=04` zawiera Kujawsko-Pomorskie i osobny status Polski.
`GET /status?regionId=04` zwraca osobno `poland`, `region` i `sourceHealth`. Pobieranie RCB startuje automatycznie i powtarza się co 5 minut; wykaz PSP odświeża się przy starcie i nie częściej niż co 6 godzin po poprawnej synchronizacji; `ENABLE_INGESTION=false` wyłącza harmonogram. `DATABASE_URL` wybiera PostgreSQL z PostGIS. Produkcja wymaga PostGIS; SQLite pozostaje wyłącznie dla testów i lokalnego developmentu.
`ADMIN_TOKEN` minimum 32 losowe znaki, wyłącznie na backendzie. Admin endpointy należy dodatkowo izolować sieciowo; panel MFA nie jest zaimplementowany.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
cd ..
API_BASE_URL=https://<wdrożony-backend> bash scripts/build-android.sh
```

Adres backendu jest dostarczany wyłącznie przez konfigurację buildu `API_BASE_URL`. Ręczne nadpisanie jest dostępne w Developer Settings w odpowiednim buildzie. Normalny użytkownik nie konfiguruje serwera. Skrypt wydania wymaga działającego backendu i poprawnej synchronizacji RCB.
Bez backendu aplikacja pokazuje brak danych. Nie korzysta bezpośrednio z API ostrzeżeń i nie udaje bieżącej oceny.

## Stan

- RCB: SourceAdapter listy komunikatów (3 strony) i pełnych artykułów, data publikacji, obszar odbiorców, ćwiczenia/odwołania, transakcyjna synchronizacja i diagnostyka źródła. To publikacje, nie kompletna lista aktywnych ostrzeżeń.
- PSP/dane.gov.pl: pełny import oficjalnego wykazu, PostGIS, wyszukiwanie adresu/gminy, stronicowanie, GeoJSON i ograniczona kopia offline. Szczegóły: [etap PSP](docs/SHELTERS_STAGE.md).
- RSO: publiczny pełny eksport XML jest podłączony do SourceAdaptera i synchronizowany co 5 minut. Komunikaty są prezentowane jako osobne źródło; aplikacja nie zgaduje, że każdy wpis RSO oznacza bezpośrednie zagrożenie.
- WCZK: rejestr 16 centrów, działający adapter Podkarpackiego oraz korelacja/deduplikacja RCB–RSO–WCZK z zachowaniem oryginalnych komunikatów.
- PAA: oficjalne komunikaty radiacyjne są podłączone; pomiary stacji pozostają wyłączone, dopóki nie ma zweryfikowanego stabilnego publicznego kontraktu danych.
- CERT Polska: oficjalny RSS komunikatów bezpieczeństwa działa jako osobna kategoria CYBER. Publiczna lista RSS CSIRT GOV jest obecnie pusta, więc integracja pozostaje NOT_CONFIGURED.
- Straż Graniczna: oficjalne Aktualności są filtrowane konserwatywnie do operacyjnych informacji o zamknięciach, ograniczeniach, kontrolach i utrudnieniach granicznych; zwykłe newsy służbowe są odrzucane.
- Policja / PSP: oficjalny RSS Aktualności Policji oraz centralne Aktualności KG PSP są filtrowane do istotnych zdarzeń sytuacyjnych (m.in. duże pożary, eksplozje, HAZMAT, rozległe ratownictwo i poważne bezpieczeństwo publiczne). Publikacje służb są osobną warstwą informacyjną i nie podnoszą automatycznie statusu całego regionu.
- Alpha.11: obserwowane lokalizacje są zapisywane lokalnie na urządzeniu; „Wokół mnie” używa jednorazowego GPS wyłącznie po akcji użytkownika. `POST /v1/around` przyjmuje współrzędne w ciele JSON (nie w URL), liczy odległość tylko dla Eventów z geometrią źródłową, a komunikaty krajowe/wojewódzkie pokazuje osobno bez udawania odległości. Brak geometrii nie jest interpretowany jako brak zdarzeń w pobliżu.
- Źródła zachowują oryginalną treść. Niepewna interpretacja nie podnosi automatycznie statusu.
- Historia wersji, korekty, widoczny timeline komunikatu, wyjaśnienie „Dlaczego taki status?”, stan źródeł, deterministyczne statusy, kopie offline, mapa MapLibre z zapytaniami bbox i klastrami PostGIS, systemowy Share Sheet dla „Jestem bezpieczny” oraz 112 wymagające działania użytkownika.
- Brakuje: alarmów Ukrainy, NEPTUN, push FCM/APNs, pełniejszego offline, RLS, panelu administratora z MFA i wdrożenia produkcyjnego.

Aktualny zakres i wdrożenie: [etap RCB](docs/RCB_STAGE.md). Hosting HTTPS nie został jeszcze uruchomiony.

Dokumentacja: [architektura](docs/ARCHITECTURE.md), [źródła](docs/SOURCES.md), [walidacja](docs/VALIDATION.md).
APK preview ma osobny identyfikator `pl.bezpiecznapolska.preview`. Podpis debug nie jest kluczem wydania do sklepu.

## Przed produkcją

Ukończyć zakres MVP, umowy/licencje źródeł, hosting z HTTPS i backupem, testy push i działania offline na prawdziwych telefonach, audyt bezpieczeństwa, politykę prywatności i podpis wydawcy. iOS wymaga macOS, konta Apple Developer i osobnej walidacji.

Nigdy nie commitować sekretów, kluczy, `.env`, baz użytkowników ani tokenów.

## Etap stopni alarmowych i MapLibre

Adapter oficjalnego HTML RCB obsługuje równoległe stopnie PHYSICAL/CRP i zakresy infrastrukturalne. `/status` zwraca osobne listy dla Polski i regionu; stopnie nie powodują automatycznie RED. Mapa używa `/v1/map/shelters?bbox=minLon,minLat,maxLon,maxLat&zoom=10`, indeksu PostGIS, klastrów i ograniczonego cache telefonu. Budowanie Androida wymaga JDK 21. Szczegóły, prawdziwe dane i ograniczenia: [raport etapu](docs/SECURITY_LEVELS_MAP_STAGE.md).
