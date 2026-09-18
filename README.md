# Bezpieczna Polska

Flutter + backend TypeScript/PostgreSQL. **0.1.0-alpha.2 — wersja rozwojowa, nie pełne MVP.**

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
`ENABLE_INGESTION=true` włącza pobieranie co 5 minut. `DATABASE_URL` wybiera PostgreSQL; bez niego używany jest lokalny SQLite.
`ADMIN_TOKEN` minimum 32 losowe znaki, wyłącznie na backendzie. Admin endpointy należy dodatkowo izolować sieciowo; panel MFA nie jest zaimplementowany.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

W ustawieniach telefonu wpisuje się adres własnego backendu HTTPS albo przekazuje `--dart-define=API_BASE_URL=https://...` przy budowaniu.
Bez backendu aplikacja pokazuje brak danych. Nie korzysta bezpośrednio z API ostrzeżeń i nie udaje bieżącej oceny.

## Stan

- RCB: parser głównej strony i treści artykułów. Niepełne pokrycie, brak potwierdzonego publicznego API.
- RSO: udokumentowany publiczny eksport XML. Regiony i ważność; semantyka czasu Europe/Warsaw wymaga potwierdzenia kontraktowego z operatorem.
- Źródła zachowują oryginalną treść. Niepewna interpretacja nie podnosi automatycznie statusu.
- Historia wersji, korekty, stan źródeł, deterministyczne statusy, kopie offline, mapa poglądowa granic, 112 wymagające działania użytkownika.
- Brakuje: pełnych adapterów WCZK/SG/CERT/PAA/Ukraina, stopni alarmowych, punktów schronienia, push FCM/APNs, MapLibre, PostGIS/RLS, panelu administratora z MFA i wdrożenia produkcyjnego.

Dokumentacja: [architektura](docs/ARCHITECTURE.md), [źródła](docs/SOURCES.md), [walidacja](docs/VALIDATION.md).
APK preview ma osobny identyfikator `pl.bezpiecznapolska.preview`. Podpis debug nie jest kluczem wydania do sklepu.

## Przed produkcją

Ukończyć zakres MVP, umowy/licencje źródeł, hosting z HTTPS i backupem, testy push i działania offline na prawdziwych telefonach, audyt bezpieczeństwa, politykę prywatności i podpis wydawcy. iOS wymaga macOS, konta Apple Developer i osobnej walidacji.

Nigdy nie commitować sekretów, kluczy, `.env`, baz użytkowników ani tokenów.
