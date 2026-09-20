# Bezpieczna Polska

Flutter + backend TypeScript/PostgreSQL. **0.1.0-alpha.3 — wersja rozwojowa, nie pełne MVP.**

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
- RSO: dotychczasowy parser XML pozostaje w testach. Synchronizacja wyłączona do jego etapu, po PSP i stopniach alarmowych.
- Źródła zachowują oryginalną treść. Niepewna interpretacja nie podnosi automatycznie statusu.
- Historia wersji, korekty, stan źródeł, deterministyczne statusy, kopie offline, mapa poglądowa granic, 112 wymagające działania użytkownika.
- Brakuje: pełnych adapterów WCZK/SG/CERT/PAA/Ukraina, stopni alarmowych, push FCM/APNs, MapLibre, RLS, panelu administratora z MFA i wdrożenia produkcyjnego.

Aktualny zakres i wdrożenie: [etap RCB](docs/RCB_STAGE.md). Hosting HTTPS nie został jeszcze uruchomiony.

Dokumentacja: [architektura](docs/ARCHITECTURE.md), [źródła](docs/SOURCES.md), [walidacja](docs/VALIDATION.md).
APK preview ma osobny identyfikator `pl.bezpiecznapolska.preview`. Podpis debug nie jest kluczem wydania do sklepu.

## Przed produkcją

Ukończyć zakres MVP, umowy/licencje źródeł, hosting z HTTPS i backupem, testy push i działania offline na prawdziwych telefonach, audyt bezpieczeństwa, politykę prywatności i podpis wydawcy. iOS wymaga macOS, konta Apple Developer i osobnej walidacji.

Nigdy nie commitować sekretów, kluczy, `.env`, baz użytkowników ani tokenów.
