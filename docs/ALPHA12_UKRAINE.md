# Alpha.12 — Ukraina

Baza: main `9c22a0625fbb89614f424ee9441d86a4f22d95bb` (integracyjny PR #12).

## Źródła i kontrakt (research 2026-09-22)

- Oficjalny system «Повітряна тривога» / UkraineAlarm, Stfalcon + Ajax Systems, dane operatorów administracji obwodowych i koordynacja DSNS.
- Potwierdzenie wydawcy: https://ajax.systems/ua/blog/air-alert-3-0/
- Oficjalny wniosek o dostęp: https://api.ukrainealarm.com/ — wymaga klucza; aplikacja nie wysyła wniosku i nie pozyskuje cudzych kluczy.
- Dokumentacja wydawcy: https://github.com/UkraineAlarm/UkraineAlarm-javascript (API v3).
- GET `https://api.ukrainealarm.com/api/v3/regions` — drzewo `states`, State/District/Community. Miasto tylko jako jednostka jawnie opisana przez źródło; nie zgadujemy typu.
- GET `/api/v3/alerts` — bieżące alerty; `lastUpdate` pozostaje czasem aktualizacji, nigdy domyślnym początkiem alarmu.
- GET `/api/v3/alerts/regionHistory?regionId=...` — według kontraktu ostatnie 25 alarmów, `startDate`, `endDate`, `isContinue`, `alertType`.
- GET `/api/v3/alerts/status` — `lastActionIndex`; sprawdzany przed i po zbiorze, zmiana indeksu odrzuca niespójny odczyt.
- Autoryzacja: nagłówek `Authorization`, sekret `UKRAINE_ALARM_API_KEY` wyłącznie na backendzie. Brak klucza = `NOT_CONFIGURED_UA_API_KEY_MISSING`.
- Geometria: publiczny serwis granic administracyjnych UN OCHA https://gis.unocha.org/server/rest/services/Hosted/UKR_Simplified_Boundaries/FeatureServer/1 . Tylko poligony, tylko jednoznaczne dokładne dopasowanie nazwy jednostki State. Brak dopasowania lub błąd dostawcy = geometria null; nie używamy centroidów, nazw podobnych ani poligonu rodzica miasta.

## Semantyka

Wspólny Event rozszerzony opcjonalnymi `origin`, `countryCode`, `ukraine`, `geometrySource`. UA ma `OFFICIAL_FOREIGN`, `countryCode=UA`, puste polskie `regions`. `INFO` jest `OFFICIAL_INFORMATION`, pozostałe obsługiwane typy `OFFICIAL_ALERT`. Nie importujemy OSINT ani pozycji/tras wojskowych.

ID cyklu wynika z regionu, typu i źródłowego początku; inny początek tworzy nowy cykl. Źródło bez początku otrzymuje cykl z nieznanym początkiem. Rewizje zachowuje istniejący Store. Korekta początku, dla którego dostawca nie ma trwałego ID cyklu, może utworzyć nowy cykl; poprzedni pozostaje UNKNOWN, bez sztucznego końca. Korekta końca jest rewizją tego samego cyklu. Brak wpisu w ograniczonej historii nie kończy zdarzenia. Znikający nierozstrzygnięty cykl przechodzi UNKNOWN z validTo=null.

UA jest wyłączona ze statusu Polski, regionalnego statusu PL, polskiego feedu i warstwy zdarzeń, korelacji oraz wyników Wokół mnie. Nie ma automatycznej propagacji zagrożenia przez granicę.

## Trwałość i offline

Eventy, rewizje i zdrowie źródła zapisują się atomowo w istniejącym PostgreSQL/PostGIS (SQLite dla testów/dev). Restart procesu lub bazy nie zeruje historii. Sukces ponownego pobrania nie tworzy identycznych rewizji. Błąd źródła zachowuje ostatni poprawny stan.

`GET /v1/ukraine`: oddzielny snapshot, sourceHealth, obwody/jednostki, wydarzenia i do 5 ostatnich rewizji na zdarzenie; do 100 zakończonych cykli plus nierozstrzygnięte (limit ochronny 1000, odmowa zamiast cichego ucięcia). Pełna historia backendu pozostaje w `/v1/events/:id/timeline`. `GET /v1/layers/ukraine.geojson`: wyłącznie administracyjne poligony aktywnych/nierozstrzygniętych alarmów.

Cache mobilny: jeden snapshot UA dla wybranego backendu, maks. 4 MiB, walidacja przed zastąpieniem, usuwany przez Wyczyść dane. Offline zawsze STALE; expiry po 180 s od sukcesu. BROKEN wyświetlany jako DOWN. Aktualność kanału nie jest dowodem braku zagrożenia: coverage maksymalnie partial, nigdy bezwarunkowy GREEN. Podkład mapy online lub z wcześniejszego cache MapLibre.

## CI i wersja

Nowy workflow `alpha12-preview.yml` dla PR do main oraz push main: backend + real PostGIS, rzeczywisty restart kontenera PostGIS i nowy proces backendu, Flutter analyze/tests, źródła live, arm64-only APK. RCB/PSP zachowują odrębne workflowy.

Stary `build.yml` jest jawnie workflowem produkcyjnym uruchamianym ręcznie. Nadal wymaga `API_BASE_URL` i pozytywnego `check-backend.mjs`; nie zastępujemy bramki atrapą backendu. Jego automatyczny build main z alpha.11 był czerwony z powodu braku API_BASE_URL. Preview pozostaje oznaczone i wymaga konfiguracji adresu backendu.

`0.1.0-alpha.12+12` (APK arm64 versionCode 2012 po dodaniu offsetu ABI Flutter), `pl.bezpiecznapolska.preview`, minSdk 24, targetSdk 36, arm64-v8a. Podpis rozwojowy preview.

## Ograniczenia

Bez autoryzowanego klucza UA dostępne są UI, cache, parser i stan NOT_CONFIGURED, ale nie bieżące alarmy. Test fixture nie zastępuje uwierzytelnionego live check. Wymagany sekret backendu i osobno sekret CI do sprawdzenia live. Nie konfigurujemy publicznego produkcyjnego wdrożenia.

Historia dostawcy jest ograniczona. Granice nie mają wspólnych identyfikatorów z UkraineAlarm: dokładne dopasowania mogą nie objąć wszystkich nazw. Brak geometrii jest widoczny. Nowy nieznany typ/zmieniony kontrakt lub zmiana alarmów podczas pobierania skutkuje odrzuceniem synchronizacji i zachowaniem last-known-good.

Alpha.13 / NEPTUN nie jest rozpoczęta.
