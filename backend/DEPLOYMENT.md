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

Backend nie odczytuje zmiennych identyfikujących konkretnego dostawcę chmury. Provider odpowiada jedynie za przetłumaczenie własnych metadanych deploymentu na powyższy kontrakt.

## Tożsamość deploymentu

`BUILD_SHA` jest jedynym źródłem prawdy dla `/health.buildSha`.

Produkcja ma odmówić startu, jeżeli `BUILD_SHA` nie jest pełnym 40-znakowym SHA. Nie należy zastępować go automatycznie zmienną specyficzną dla Railway, Oracle, GitHub Actions ani innego dostawcy.

Runtime audit może dodatkowo otrzymać `EXPECTED_BUILD_SHA` i wymaga wtedy dokładnej zgodności działającego backendu z oczekiwanym deploymentem.

## Publiczny adres

Workflowy i buildy aplikacji nie zawierają wpisanego na stałe hosta dostawcy.

Używane są:

- `PRODUCTION_API_BASE_URL` — produkcyjny backend,
- `PREVIEW_API_BASE_URL` — opcjonalny osobny backend preview,
- jeżeli preview nie ma osobnego backendu, może jawnie użyć `PRODUCTION_API_BASE_URL`,
- `API_BASE_URL` pozostaje wyłącznie tymczasowym, provider-neutral aliasem migracyjnym dla istniejącej konfiguracji GitHub Actions i ma zostać usunięty po ustawieniu docelowych zmiennych.

Brak obu zmiennych w buildzie preview jest błędem konfiguracji, a nie sygnałem do użycia ukrytego fallbacku.

## Obecny adapter Railway

Do czasu migracji produkcji Railway nadal śledzi `main` i `backend/**`.

Railway udostępnia własne metadane Git deploymentu. Na poziomie konfiguracji usługi zmienna ogólna `BUILD_SHA` jest mapowana na SHA bieżącego deploymentu Railway. Jest to adapter hostingu poza kodem aplikacji; po przejściu na Oracle zostanie zastąpiony ustawieniem `BUILD_SHA` przez nowy pipeline wdrożeniowy.

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
