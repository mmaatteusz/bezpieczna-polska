# Production deployment contract

Backend produkcyjny ma być niezależny od dostawcy hostingu. Kod aplikacji zna wyłącznie ogólny kontrakt wdrożenia:

- `APP_ENV=production`,
- `NODE_ENV=production`,
- `BUILD_SHA=<dokładny 40-znakowy SHA wdrożonego commita>`,
- `PUBLIC_BASE_URL=https://<publiczny-host-api>`,
- `DATABASE_URL=<PostgreSQL/PostGIS>`,
- wymagane sekrety i ustawienia produkcyjne,
- migracja `node dist/migrate.js` przed uruchomieniem API,
- healthcheck `/ready`,
- runtime audit kierowany przez `PRODUCTION_API_BASE_URL`.

Nowe wdrożenia ustawiają ogólny BUILD_SHA. Dla starszego środowiska Railway zachowany jest ograniczony adapter zgodności opisany poniżej.

## Tożsamość deploymentu

`BUILD_SHA` ma pierwszeństwo dla `/health.buildSha`, także gdy metadata hostingu zawiera inny SHA.

Produkcja odmawia startu, jeśli jawnie ustawiony BUILD_SHA jest niepoprawny. Gdy zmienna jest całkowicie nieobecna, starsze wdrożenie Railway może użyć poprawnego RAILWAY_GIT_COMMIT_SHA. To zgodność na czas przejścia; nowe środowiska powinny zawsze ustawiać BUILD_SHA.

Runtime audit może dodatkowo otrzymać `EXPECTED_BUILD_SHA` i wymaga wtedy dokładnej zgodności działającego backendu z oczekiwanym deploymentem.

## Publiczny adres

Workflowy i buildy aplikacji nie zawierają wpisanego na stałe hosta dostawcy.

Używane są:

- `PRODUCTION_API_BASE_URL` — produkcyjny backend,
- `PREVIEW_API_BASE_URL` — opcjonalny osobny backend preview,
- jeżeli preview nie ma osobnego backendu, może jawnie użyć `PRODUCTION_API_BASE_URL`.

Brak obu zmiennych w buildzie preview jest błędem konfiguracji, a nie sygnałem do użycia ukrytego fallbacku.

## Obecny adapter Railway

Do czasu migracji produkcji Railway nadal śledzi `main` i `backend/**`.

Railway udostępnia własne metadane Git deploymentu. Zalecane jest mapowanie zmiennej BUILD_SHA na SHA bieżącego deploymentu Railway. Do czasu takiej konfiguracji backend obsługuje dotychczasowe metadata jako fallback. Ta integracja nie zmienia zmiennych usługi ani adresów API.

## Docelowy adapter Oracle

Pipeline Oracle ma:

1. wdrożyć konkretny commit/obraz,
2. ustawić `BUILD_SHA` na SHA tego commita,
3. wykonać migracje,
4. uruchomić API,
5. sprawdzić `/ready`,
6. uruchomić provider-neutral runtime audit przeciwko `PRODUCTION_API_BASE_URL`,
7. umożliwiać rollback do konkretnego obrazu/commita z odpowiadającym mu `BUILD_SHA`.

Dzięki temu zmiana hostingu nie wymaga zmian w logice backendu ani w aplikacji mobilnej.
