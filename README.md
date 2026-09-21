# Bezpieczna Polska

Flutter + backend TypeScript/PostgreSQL. **0.1.0-alpha.10 — wersja rozwojowa, nie pełne MVP.**

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
- Źródła zachowują oryginalną treść. Niepewna interpretacja nie podnosi automatycznie statusu.
- Historia wersji, korekty, widoczny timeline komunikatu, wyjaśnienie „Dlaczego taki status?”, stan źródeł, deterministyczne statusy, kopie offline, mapa MapLibre z zapytaniami bbox i klastrami PostGIS, systemowy Share Sheet dla „Jestem bezpieczny” oraz 112 wymagające działania użytkownika.
- Brakuje: pełnych obserwowanych lokalizacji i „wokół mnie”, alarmów Ukrainy, NEPTUN, push FCM/APNs, RLS, panelu administratora z MFA i wdrożenia produkcyjnego.

Aktualny zakres i wdrożenie: [etap RCB](docs/RCB_STAGE.md). Hosting HTTPS nie został jeszcze uruchomiony.

Dokumentacja: [architektura](docs/ARCHITECTURE.md), [źródła](docs/SOURCES.md), [walidacja](docs/VALIDATION.md).
APK preview ma osobny identyfikator `pl.bezpiecznapolska.preview`. Podpis debug nie jest kluczem wydania do sklepu.

## Przed produkcją

Ukończyć zakres MVP, umowy/licencje źródeł, hosting z HTTPS i backupem, testy push i działania offline na prawdziwych telefonach, audyt bezpieczeństwa, politykę prywatności i podpis wydawcy. iOS wymaga macOS, konta Apple Developer i osobnej walidacji.

Nigdy nie commitować sekretów, kluczy, `.env`, baz użytkowników ani tokenów.

## Etap stopni alarmowych i MapLibre

Adapter oficjalnego HTML RCB obsługuje równoległe stopnie PHYSICAL/CRP i zakresy infrastrukturalne. `/status` zwraca osobne listy dla Polski i regionu; stopnie nie powodują automatycznie RED. Mapa używa `/v1/map/shelters?bbox=minLon,minLat,maxLon,maxLat&zoom=10`, indeksu PostGIS, klastrów i ograniczonego cache telefonu. Budowanie Androida wymaga JDK 21. Szczegóły, prawdziwe dane i ograniczenia: [raport etapu](docs/SECURITY_LEVELS_MAP_STAGE.md).
