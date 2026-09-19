# Etap 1: RCB i podstawa backendu

Zakres: RCB, wspólny Event, PostGIS, /status, sourceHealth, konfiguracja buildu.
Interfejs i nawigacja pozostają. Kolejne integracje nie są uruchamiane jednocześnie.

## Kontrakt RCB

Źródło: https://www.gov.pl/web/rcb/komunikaty, publiczne HTML, bez autoryzacji.
SourceAdapter `rcb-html/1.0.0` odczytuje maksymalnie 3 strony listy (do 30 wpisów),
następnie pełne artykuły. Maksymalnie 3 równoległe pobrania, timeout 20 s,
limit dokumentu 4 MiB, HTTPS, kontrola hosta, brak przekierowań.
Synchronizacja automatyczna po starcie serwera i co 5 minut; wspólna blokada
chroni przed nakładaniem wywołania harmonogramu i administratora.

Zapis całej paczki i sourceHealth jest transakcyjny. Błąd dowolnego dokumentu
nie publikuje częściowego sukcesu, zachowuje ostatnią kopię i lastSuccess.
sourceHealth zawiera lastSuccessfulSyncAt, lastAttemptAt, lastFailure,
errorCode, failureCount, itemCount, adapterVersion, responseTime i TTL.
Po przekroczeniu TTL API zwraca STALE, mimo że serwer HTTP nadal działa.

Data dzienna jest przechowywana jako publicationDate. publishedAt pozostaje
null, gdy urząd nie udostępnia godziny. Nie wyliczamy fikcyjnego validTo.
Regiony pochodzą z sekcji odbiorców i jawnej listy województw. Powiat opolski
nie oznacza woj. opolskiego. PROVINCE_SUBSET oznacza część województwa.
Brak rozpoznanej geografii oznacza UNKNOWN. Nie wymyślamy współrzędnych.
Ćwiczenia/testy są oddzielone od rzeczywistych komunikatów. Publikacja odwołania
nie odwołuje automatycznie innego rekordu bez jednoznacznego powiązania.

To zbiór ostatnich publikacji, a nie kompletna lista aktywnych zagrożeń.
Dlatego complete=false i coverage=RECENT_PUBLICATIONS także po poprawnym
pobraniu. Brak nowego wpisu nie daje zielonego statusu. Autentyczność publikacji
CONFIRMED nie oznacza potwierdzonej bieżącej ważności.

## API / dane przestrzenne

- GET /status?regionId=04: niezależne poland i region oraz sourceHealth.
- GET /v1/snapshot?regionId=04: kompatybilny kontrakt obecnego UI, te same reguły.
- GET /v1/sources: stan wszystkich źródeł; niewłączone oznaczone NOT_CONFIGURED.
- GET /v1/layers/events.geojson?regionId=PL&bbox=14,49,24,55: GeoJSON z geometrii
  dostarczonych przez źródło. Brak geometrii = brak punktu na mapie, nie punkt
  w środku województwa. RCB nadal dostępne na liście.
- /healthz: proces HTTP; /readyz: baza i aktualna poprawna synchronizacja
  włączonych źródeł. Gotowość techniczna nie oznacza braku zagrożeń.

PostGIS: rozszerzenie, geometria EPSG:4326, indeks GiST, ST_Intersects z bbox,
walidacja ST_IsValid i wybór wyłącznie ostatniej rewizji zdarzenia.
SQLite służy tylko lokalnemu developmentowi/testom; produkcja wymaga DATABASE_URL.
Migracja jest addytywna i idempotentna. Nie kasuje istniejących rewizji.

## Aplikacja / wydanie

API_BASE_URL pochodzi z --dart-define. Stare ustawienie `api` jest ignorowane.
Ręczne nadpisanie jest w Developer Settings, kontrolowanych flagą
ENABLE_DEVELOPER_SETTINGS (domyślnie tylko debug). Wyłączenie flagi ignoruje
zapisane nadpisanie. Puste pole deweloperskie przywraca adres z buildu.
Aplikacja pobiera dane po uruchomieniu, po powrocie i co minutę na pierwszym planie.
Normalne ustawienia nie zawierają adresu serwera. Brak konfiguracji buildu
jest błędem wydania, nie zadaniem dla użytkownika.

`scripts/build-android.sh` sprawdza działający HTTPS /readyz, PostGIS,
synchronizację RCB i kontrakt mobilny, następnie przekazuje adres do kompilacji.
Nie używać starego workflow tworzącego alpha.2 bez API_BASE_URL jako wydania
tego etapu. Nie budować użytkowego APK przed uruchomieniem backendu.

## Wdrożenie — brakuje docelowego hosta

Przygotowane pliki są gotowe do uruchomienia na hoście Docker z domeną:

```
export API_DOMAIN=<domena-skierowana-na-host>
export POSTGRES_PASSWORD=<losowe-znaki-hex>
export ADMIN_TOKEN=<co-najmniej-32-losowe-znaki>
docker compose -f compose.yaml -f deploy/compose.https.yaml up -d --build
export API_BASE_URL=https://$API_DOMAIN
bash scripts/build-android.sh
```

Caddy zapewnia TLS i nie wystawia /admin przez publiczną domenę. PostgreSQL
nie ma opublikowanego portu, dane w trwałym woluminie. Sekrety na hoście,
poza repozytorium i APK. Operator hosta musi zapewnić kopie bazy.
Te polecenia nie zostały wykonane na publicznym serwerze; brak domeny,
hostingu i dostępu wdrożeniowego. Nie deklarować działania na telefonie.

## Następne etapy (w tej kolejności)

1. PSP/dane.gov.pl — weryfikacja kontraktu, rodzaju i aktualności punktów schronienia.
2. Stopnie alarmowe RP.
3. RSO/WCZK (stary parser XML jest zachowany do testów, harmonogram wyłączony).
4. PAA.
5. CERT Polska.
6. Straż Graniczna.
7. Oficjalne alarmy Ukrainy; agregator nie jest automatycznie źródłem urzędowym.
8. MapLibre zamiast Natural Earth, z warstwami GeoJSON i licencjonowanym podkładem.

Po każdym adapterze: test kontraktowy, błędy i aktualność, rzeczywisty odczyt
z podaniem daty i URL, dopiero potem jego włączenie.
