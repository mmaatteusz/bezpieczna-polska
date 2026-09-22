# Alpha.13 — NEPTUN

Baza etapu: `main` po alpha.12 (`204bbfc5ed4cd0923132dfd6241d70ca17298982`).

## Cel

NEPTUN jest osobnym modułem OSINT pokazującym **historyczny rozwój zakończonych zdarzeń**: kolejne obserwacje, źródło i czas każdej obserwacji, zgrubny przebieg, kierunek opisowy, korekty i historię rewizji.

NEPTUN nie jest częścią statusu Polski, korelacji RCB/RSO/WCZK ani funkcji „Wokół mnie”.

## Zasady bezpieczeństwa publikacji

Publiczne API NEPTUN stosuje niezależne bramki:

- tylko `lifecycle=ENDED`;
- minimum 24 godziny od zakończenia śladu do publikacji;
- współrzędne są publikowane wyłącznie ze wskazaną niepewnością co najmniej 10 km;
- publiczna odpowiedź dodatkowo zgrubnia współrzędne zgodnie z deklarowaną niepewnością;
- brak aktywnych dokładnych pozycji;
- brak velocity, headingu liczbowego, identyfikatorów jednostek lub telemetrycznych danych operacyjnych;
- brak wymyślania współrzędnych, czasu lub kierunku;
- każda obserwacja zachowuje własne źródło, URL, origin i semantyczny poziom weryfikacji bez sztucznych procentów.

Nie ma skonfigurowanego automatycznego feedu NEPTUN. Ślady mogą być zapisane wyłącznie przez autoryzowany endpoint operatora po ręcznej weryfikacji. Brak danych nie oznacza braku zdarzeń.

## Model

Ślad przechowuje:

- stabilne `id`;
- typ obiektu/zdarzenia;
- `startedAt` i źródłowe `endedAt`;
- semantyczne `verification`;
- opcjonalny `directionText`;
- chronologiczne obserwacje;
- przy obserwacji: czas, opis obszaru, opcjonalną zgrubną geometrię, `precisionKm`, źródło, korektę i weryfikację;
- audytowaną historię rewizji.

Magazyn: `neptun_track_revisions`. Korekty są append-only.

## API

- `GET /v1/neptun` — bounded historyczny snapshot.
- `GET /v1/layers/neptun.geojson` — tylko zgrubne `LineString` dla śladów mających co najmniej dwie obserwacje z geometrią.
- `GET /v1/neptun/:id/timeline` — historia rewizji i zmienione pola.
- `POST /admin/neptun` — autoryzowany zapis/korekta, optimistic revision i wymagany powód.

Odpowiedź deklaruje `mode=HISTORICAL_ONLY`, `safetyDelayHours=24` i `minimumPublishedPrecisionKm=10`.

## Mobile

Flutter ma osobny ekran **NEPTUN • historia**:

- trwały last-known-good cache per backend;
- lista zakończonych śladów;
- timeline obserwacji;
- źródło każdej obserwacji;
- kierunek opisowy;
- mapa z historycznymi liniami;
- jawny komunikat, że brak śladów nie oznacza braku zdarzeń;
- jawny komunikat, że moduł nie pokazuje aktywnych dokładnych pozycji.

Usunięcie danych aplikacji usuwa również cache NEPTUN.

## Ograniczenia

Alpha.13 nie uruchamia automatycznego źródła OSINT. Nie kwalifikujemy żadnego zewnętrznego feedu jako produkcyjnego bez osobnego audytu pochodzenia, licencji, opóźnienia i semantyki geometrii.

NEPTUN nie zastępuje oficjalnych alarmów Ukrainy ani komunikatów polskich służb i nie podnosi statusu zagrożenia.

Następny etap roadmapy: push FCM/APNs.
