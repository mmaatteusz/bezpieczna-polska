# Etap PSP / dane.gov.pl

## Źródło i znaczenie danych

Zbiór [Punkty schronienia w Polsce](https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce), ID 28058, wydawca Komenda Główna PSP (instytucja 22), CC BY 4.0.
Adapter weryfikuje metadane dane.gov.pl, następnie pobiera [katalog XML PSP](https://gdziesieukryc.pl/PS_XML/punkty_schronienia.xml) oraz wskazany tam [CSV](https://gdziesieukryc.pl/PS_XML/punkty_schronienia.csv). Pobiera katalog ponownie, aby wykryć zmianę wersji podczas transferu.
Bezpośredni eksport PSP jest nowszy niż buforowany zasób dane.gov.pl; to ten sam zadeklarowany przez wydawcę kanał publikacji.

Punkt w wykazie nie jest automatycznie certyfikowanym schronem. Typ źródłowy to „Obiekt ochrony ludności”; brak klasy ochrony, pojemności, dokładnych godzin i informacji o dostępności dla osób z niepełnosprawnościami. Pola pozostają UNKNOWN/null. „Całodobowa”, „Na żądanie” i „Określone godziny” to oznaczenia wydawcy, nie potwierdzenie wejścia teraz.
Oficjalne wyjaśnienie: https://www.gov.pl/web/kmpsp-warszawa/gdzie-sie-ukryc---sprawdz-najblizsze-punkty-schronienia-ps

## Synchronizacja i przechowywanie

- Jeden SourceAdapter SHELTERS, uruchamiany automatycznie wraz z RCB. Poprawny import nie częściej niż co 6 h; po awarii ponowna próba w następnym cyklu backendu.
- Kontrakt sprawdza wydawcę, licencję, dokładne adresy zasobów, nagłówki CSV, liczbę wierszy, identyfikatory, regiony, współrzędne i daty. Niekompletny zbiór jest odrzucany w całości.
- Atomowa zamiana krajowego wykazu i sourceHealth w jednej transakcji. Usunięte punkty znikają po poprawnym imporcie. Błąd pozostawia poprzednie punkty, skrót i czas ostatniego sukcesu; stan źródła jest BROKEN.
- sourceHealth zawiera lastSuccessfulSyncAt, dataDate, sourceUpdatedAt, liczbę punktów, SHA-256 CSV i licencję. Po 48 h bez poprawnej synchronizacji lub wieku eksportu ponad 14 dni dane są STALE. To polityka aplikacji, nie deklarowana przez PSP gwarancja aktualizacji.
- Osobny model Shelter dla stałych obiektów. Zunifikowany Event pozostaje modelem ostrzeżeń. Katalog obiektów nigdy nie potwierdza braku zagrożeń i nie daje GREEN.
- PostGIS Point/SRID 4326, indeks GiST, filtrowanie bbox; SQLite wyłącznie w development/testach.

## API i telefon

`GET /v1/shelters?regionId=04&q=Bydgoszcz&limit=50&offset=0`
`GET /v1/layers/shelters.geojson?regionId=04&bbox=17.8,53,18.3,53.3&limit=50`

Limit 1–500 (domyślnie 50), region PL lub kod województwa. Wyszukiwanie dosłownego tekstu adresu/gminy/powiatu, bez rozróżniania polskich znaków. Stabilna kolejność ID. Kolejne strony przesyłają `version` (SHA-256 zawartości). Zmiana danych daje 409 SHELTER_VERSION_CHANGED; telefon wraca do pierwszej strony, nie łączy wersji. GeoJSON zachowuje [longitude, latitude] i tę samą paginację. Odbiorca warstwy musi obsłużyć hasMore; nie jest to cała Polska w jednej odpowiedzi.

Snapshot zawiera pierwszą stronę regionu, więc start aplikacji automatycznie pobiera punkty z backendu wskazanego w buildzie. Obecna zakładka schronienia zawiera wyszukiwarkę, strony wyników, daty i jawne braki danych. Offline dostępna jest pierwsza strona ostatniego snapshotu i ostatnia strona wyszukiwania dla serwera/regionu, a nie pełny regionalny pakiet. Usunięcie danych unieważnia trwające żądania. Nie dodano GPS ani automatycznej nawigacji.

Mapa Natural Earth pozostaje do etapu MapLibre. Warstwa GeoJSON jest gotowa do podłączenia. Żadne kolejne źródła nie zostały włączone.

## Weryfikacja

TypeScript build poprawny. Testy backendu obejmują rzeczywisty PostGIS, transakcyjny rollback, geometrię, bbox i diagnostykę HTTP. Flutter analyze/test obejmuje modele, kopię offline i ekran przy czcionce 200%.

Przebieg CI z 19 września: https://github.com/mmaatteusz/bezpieczna-polska/actions/runs/35465820933 — backend/PostGIS i Flutter przeszły, a próba sieciowa PSP zakończyła się błędem HTTP. Diagnostyka z 20 września: https://github.com/mmaatteusz/bezpieczna-polska/actions/runs/35491250947 — dane.gov.pl HTTP 200, katalog XML i CSV PSP HTTP 403 „Dostęp zablokowany - Safe Place Admin”. Nie obchodzimy tej blokady. Docelowy host wymaga sprawdzenia dostępu do PSP; bramka wydania nadal wymaga udanej synchronizacji.

Pełny import z bieżącego środowiska powiódł się ponownie 20 września 2026 o 05:17 UTC. Rozdzielamy deterministyczne testy kodu od dostępności źródła z konkretnej maszyny: nie wolno przedstawiać błędu próby sieciowej jako sukcesu integracji na tej maszynie.

Kopia dane.gov.pl nie jest automatycznym fallbackiem: download_url przekierowuje do PSP. Opis zasobu wskazuje 85 762 rekordy (data_date 2026-09-14), podczas gdy API tabular_data zwraca count 81 967 i widoczne rekordy z updated_at 2026-03-10. Bez uzgodnienia kompletności i dat nie publikujemy tego jako pełnej aktualnej kopii.

Rzeczywista obserwacja 2026-09-19: 85 889 punktów PL, 4 064 w kujawsko-pomorskim, 449 wyników dla Bydgoszczy. Eksport PSP z 2026-09-19 08:24:06 +02:00. Pełne metadane i przykłady: [raport](validation/shelters/shelters-live.json). Skrypt ponowienia: `node backend/scripts/live-shelters.mjs docs/validation/shelters` po kompilacji backendu; TEST_DATABASE_URL wybiera bazę testową PostGIS.

Przykłady z odpowiedzi API:
- ul. Kormoranów 54, Bydgoszcz — Na żądanie.
- ul. Gołębia 66A, Bydgoszcz — Określone godziny (bez godzin w źródle).
- ul. Hutnicza 89, Bydgoszcz — Na żądanie.

Fixture backendu zawiera trzy rzeczywiste rekordy; liczbę w katalogu testowym zmniejszono do 3. Fixture Fluttera jest podzbiorem odpowiedzi API (3 rekordy, zmniejszona liczba wyników); dane: KG PSP, CC BY 4.0. Fixture nie trafiają do aplikacji produkcyjnej.

Publiczny backend HTTPS nadal nie został wdrożony. Ten etap nie tworzy gotowego APK z działającym publicznym serwerem. Bramka wydania sprawdza PostGIS, RCB i PSP; nie dopuszcza pustego ani fikcyjnego URL.
