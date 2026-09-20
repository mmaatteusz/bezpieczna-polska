# Stopnie alarmowe RP i podstawowa mapa MapLibre

Stan prac: 20.09.2026. Bez dużego redesignu UI. Nie wdrożono RSO/WCZK ani kolejnych źródeł.

## Źródło i rzeczywiste dane

Adapter `LEVELS` czyta HTML oficjalnego archiwum https://www.gov.pl/web/rcb/komunikaty i wskazane w nim artykuły RCB. Nie korzysta z wymyślonego API. Nie znaleziono zweryfikowanego publicznego API rejestru aktualnych stopni; wdrożony mechanizm odpowiada publikacji komunikatów HTML.

Rzeczywiście pobrany komunikat: https://www.gov.pl/web/rcb/przedluzenie-obowiazywania-stopni-alarmowych-do-30-listopada-2026-r (publikacja 26.08.2026, zarządzenia PRM z 25.08.2026).

| Zarządzenie | Stopień | Zakres |
| --- | --- | --- |
| 47/2026 | BRAVO / PHYSICAL | Całe terytorium RP |
| 48/2026 | CHARLIE / PHYSICAL | Linie kolejowe zarządzane przez PKP Polskie Linie Kolejowe S.A. oraz PKP Linię Hutniczą Szerokotorową sp. z o.o. |
| 49/2026 | BRAVO / PHYSICAL | Polska infrastruktura energetyczna poza granicami RP |
| 50/2026 | BRAVO-CRP / CRP | Całe terytorium RP |

Wszystkie obowiązują od 1.09.2026 00:00 do 30.11.2026 23:59 czasu Warszawy. Koniec minuty zapisany jest jako `2026-11-30T22:59:59.999Z`. Zakresów infrastrukturalnych nie zamieniamy na arbitralny promień ani wielokąt. Źródło nie publikuje geometrii, więc `geometry=null`. Podaje datę publikacji bez godziny: zachowujemy jej dokładność. `updatedAt=null`, gdy brak informacji źródłowej. Czas pobrania jest osobnym `retrievedAt` / `lastSuccess`.

Raport rzeczywistego pobrania: `docs/validation/levels/levels-live.json`; raport CI: `docs/validation/levels-ci/levels-live.json`. HTML fixtures pochodzą z gov.pl, nie są alertami produkcyjnymi. Osiem zapisanych decyzji w raporcie obejmuje cztery już wygasłe i cztery aktywne; `/status` pokazuje tylko aktywne.

## Adapter, model i status

- Wszystkie cztery stopnie PHYSICAL oraz cztery CRP. Osobny wpis dla każdej decyzji, bez globalnego `alarmLevel`.
- Pola: id, level, type, scope, area, description, regions, geometry, validFrom, validTo, issuedBy, sourceUrl, publishedAt, updatedAt, rawSourceId, isActive. Dane rozszerzają wspólny Event i jego historię rewizji.
- Stabilny identyfikator z numeru i roku zarządzenia; deduplikacja i odrzucanie sprzecznych duplikatów. Zmiana końca obowiązywania tworzy rewizję, ponowne pobranie tej samej treści nie tworzy nowej.
- Aktywność w zapisanej rewizji odzwierciedla pobranie; API i telefon przeliczają ją względem aktualnego czasu. Sam upływ czasu nie tworzy fikcyjnej zmiany komunikatu.
- Wykrywanie zmiany struktury, błędnej daty, nieznanego stopnia, sprzeczności, pustej odpowiedzi i błędów HTTP. Błąd zachowuje ostatni poprawny zapis i oznacza źródło jako niesprawne/STALE.
- Archiwum sprawdzane do 120 dni wstecz, najwyżej 40 stron, odpytywanie poprawnego źródła co godzinę. Istniejące decyzje pozostają w historii. To wykaz na podstawie publikacji, nie gwarantowany kompletny rejestr państwowy (`complete=false`, `PUBLISHED_DECISIONS_ONLY`). Nowa nieobsługiwana forma uchylenia/zmiany wymaga przeglądu parsera i powoduje STALE; nie zgadujemy skutków prawnych.
- `sourceHealth`: lastSuccess, lastFailure, responseTime, failureCount, lastItemTime, healthStatus, TTL i szczegóły błędu.
- `/status?regionId=04`: `securityLevels` na poziomie odpowiedzi oraz oddzielnie `poland.securityLevels` i `region.securityLevels`; `securityLevelsStatus`, czas synchronizacji i opis ograniczeń. Zagraniczna infrastruktura nie jest przypisywana automatycznie województwu. CHARLIE dla kolei pozostaje opisem infrastruktury, nie ogólnym CHARLIE dla wszystkich mieszkańców.
- Stopnie są kontekstem gotowości (`ADMINISTRATIVE_READINESS_LEVELS`), nie samodzielnym dowodem zagrożenia. Nie tworzą automatycznie RED i nie są alertami RCB w strumieniu zdarzeń.
- `/v1/snapshot` zawiera sekcję regionalną i `nationalSecurityLevels`; awaria źródła ani brak danych nie dają GREEN.

## UI i offline

Na istniejącym ekranie Status dodano sekcję „Stopnie alarmowe”: poziom, obszar, termin, oficjalne źródło i wyjaśnienie znaczenia. Bez przebudowy nawigacji.

Sekcja zapisuje się w istniejącym cache snapshotów oddzielnie dla serwera i regionu. Awaria pobrania nie niszczy ostatniej poprawnej kopii. Offline widoczny jest napis „Ostatnie zapisane dane”, „Aktualność” i niepotwierdzona świeżość. Ważność i TTL są przeliczane również lokalnie. Wygasłego wpisu nie prezentujemy jako obowiązującego. Backend URL pozostaje konfiguracją buildu z ewentualnym nadpisaniem tylko w Developer Settings.

## MapLibre i endpointy mapy

Natural Earth zastąpiono MapLibre GL Flutter 0.27.1, bez zmiany układu ekranu. Podkład OpenFreeMap Liberty jest ustawiony w buildzie (`MAP_STYLE_URL`), z atrybucją OpenFreeMap / OpenMapTiles / OpenStreetMap. Brak klucza API i ustawień serwera dla użytkownika. Natywna mapa wymaga Android JDK 21 podczas budowania.

Nowe endpointy:

- `/v1/map/shelters?bbox=17.8,53,18.3,53.3&zoom=10&regionId=04&availability=ALL`
- `/v1/map/layers`

Bbox jest obowiązkowy i walidowany. PostGIS używa `ST_Intersects` i istniejącego indeksu GiST; SQLite zwraca 503. Zapytania i metadane pochodzą z jednej transakcji REPEATABLE READ. Do 500 punktów zwracamy pełne szczegóły. Powyżej progu SQL agreguje wszystkie trafienia w siatce maksymalnie 33×33 komórek. Żadne schronienia nie giną wskutek arbitralnego limitu strony; suma liczników odpowiada liczbie punktów w bbox. Liczniki są lokalne dla widoku i filtra, nie dla całego kraju.

Telefon pobiera widok po zatrzymaniu kamery (350 ms debounce), odrzuca spóźnione odpowiedzi, umożliwia zoom, dotknięcie klastra, wybór punktu i filtr dostępności wg źródła. Szczegóły pokazują datę i źródło, nie obiecują bieżącego dostępu ani klasy ochronnej.

Cache jest po stronie telefonu: maksymalnie cztery odpowiedzi, każda do 2 MiB, klucz obejmuje backend, region, bbox, zoom i filtr. Nie pobieramy całych 85 tys. punktów przy otwarciu mapy. Nie ma drugiego cache serwerowego na tym etapie. Offline można użyć zgodnego zapisanego widoku, zawsze z oznaczeniem niepotwierdzonej aktualności. To nie jest pełny pakiet offline kraju; podkład zależy od internetu / natywnego cache kafelków. Brak danych w bieżącym obszarze nie jest zastępowany punktami z innego obszaru.

## Kolejne warstwy

Wspólny envelope: GeoJSON FeatureCollection + metadata (schemaVersion, layerId, authority, regionId, bbox, zoom, filtr, version, health, dataDate, sourceUrl, serverTime). Flutter ma interfejs `MapLayerProvider`; backend rejestr warstw. Tylko shelters jest aktywna; RCB, RSO/WCZK, radiation, border, police/PSP, Ukraine alerts i NEPTUN są zarezerwowane, bez fikcyjnych danych.

NEPTUN pozostaje przyszłym SourceAdapterem i ma odrębną tożsamość `NEPTUN`, authority `OSINT`, nigdy `OFFICIAL_PL`/RCB. Przyszły kontrakt zdarzenia musi zachować: rodzaj UAV/missile/ballistic/KAB/alarm, observedAt, zakres czasu, przybliżony kierunek, metodę i niepewność pozycji, pochodzenie, status weryfikacji oraz lifecycle/historyczny ślad po zakończeniu. Nie rysować dokładnej pozycji, jeżeli źródło daje tylko kierunek lub obszar. Nie zaimplementowano jeszcze pobierania NEPTUN.

## PSP HTTP 403 i fallback

Ograniczona diagnostyka bez spoofingu, zmiany adresu IP, agresywnych ponowień czy obchodzenia kontroli. Raporty: `docs/validation/psp-http-local/psp-http.json`, CI `docs/validation/psp-http/psp-http.json`.

| Próba | Środowisko robocze | GitHub Actions |
| --- | --- | --- |
| Oficjalny XML, HTTP/1.1 | 200 | 403 |
| Oficjalny XML, HTTP/2 | 200 | 403 |
| API metadanych dane.gov.pl | 200 | 200 |
| Pobranie pliku przez dane.gov.pl | 302 do PSP | 302 do PSP |

403 ma nagłówki Cloudflare i tytuł „Dostęp zablokowany - Safe Place Admin”. Standardowe nagłówki Accept i jawny identyfikator aplikacji nie rozwiązują problemu. Nie stwierdzono 429 ani Retry-After. Obserwacje wskazują ograniczenie zależne od środowiska klienta; konkretnej reguły WAF/ASN/IP/geolokalizacji nie da się potwierdzić bez logów administratora PSP. Nie deklarujemy, że blokada została usunięta.

Publiczny kanał XML/CSV jest wskazany w oficjalnych metadanych zbioru 28058. Download dane.gov.pl nie jest niezależną kopią. Sprawdzony kanał tabelaryczny zasobu 1393918 zwracał 81 967 rekordów i daty z marca; metadane zbioru/plik PSP wskazywały inny, nowszy stan. Bez sprawdzenia kompletności i spójności nie przełączamy na niego produkcyjnego importu.

Polityka: PRIMARY_OFFICIAL_SOURCE → SECONDARY_OFFICIAL_SOURCE (tylko po walidacji niezależności, pełności i daty) → LAST_KNOWN_GOOD_COPY. Obecnie secondary ma jawny stan NOT_VERIFIED, dlatego wykonany fallback to ostatnia poprawna baza + cache telefonu. Health udostępnia wybrany wariant i powód. Bez jakiegokolwiek poprawnego importu wariant to NONE/UNKNOWN, nie pusty „aktualny” katalog.

## Weryfikacja i pozostałe zadania

Wyniki i odnośniki do CI należy czytać w końcowym raporcie walidacji tego etapu. Lokalnie: 64 testy backendu, 62 PASS, 2 testy PostGIS pominięte, ponieważ lokalnie brak PostgreSQL; PostGIS uruchamiany w CI. Testy parsera obejmują wszystkie osiem stopni, jednoczesność, region/infrastrukturę, daty/DST, przedłużenie, korektę, wygaśnięcie, duplikaty, zmianę HTML, pusty/błędny/niedostępny serwis i zachowanie ostatniej kopii. Testy przestrzenne obejmują bbox, region/filtr, 1200 punktów testowych i zachowanie ich liczby w klastrach, mały viewport i nową wersję importu.

Do pozostawienia po tym etapie: potwierdzenie zachowania natywnej mapy na fizycznym Androidzie, dalsza obsługa zmian formatu publikacji, uzgodnienie dostępu PSP z operatorem lub zweryfikowanie niezależnej pełnej dystrybucji. Publiczny backend/domena i produkcyjne podpisywanie APK nie zostały skonfigurowane. Nie ma produkcyjnego APK z działającym publicznym serwerem. Brak fikcyjnego backend URL.
