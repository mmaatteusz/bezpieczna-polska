# Alpha.15 — pełniejsze pakiety offline regionu

Alpha.15 dodaje przygotowywane z wyprzedzeniem pakiety dla województwa lub — jeżeli mieści się w bezpiecznym limicie — całej Polski. Pakiet jest **last-known-good snapshotem**, nigdy źródłem danych LIVE.

## Zawartość

Pakiet zawiera stan z `/v1/snapshot`, Eventy i Incidenty, sourceHealth z chwili pobrania, stopnie alarmowe, PAA, pełny katalog punktów schronienia wybranego regionu, lokalną konfigurację obserwowanych miejsc oraz lokalne overlaye danych. Alarmy Ukrainy i NEPTUN nie są częścią polskiego pakietu i zachowują oddzielne lifecycle/cache.

Manifest zawiera `regionId`, `createdAt`, `dataTimestamp` / `snapshotTimestamp`, `schemaVersion`, wersję aplikacji, opcjonalną wersję backendu, timestampy źródeł, rozmiar payloadu, listę komponentów i warstw, wersję danych schronień oraz checksum CRC32 do detekcji uszkodzeń.

## Atomiczność i integrity

Zapis używa kolejności:

1. staging,
2. ponowne odczytanie i walidacja struktury,
3. walidacja checksumy, schemaVersion, zakresów i wymaganych komponentów,
4. zapis kandydata,
5. atomowa logicznie aktywacja przez zmianę wskaźnika active,
6. dopiero po aktywacji usunięcie poprzedniej wersji.

Błąd pobierania albo walidacji nie zmienia aktywnego pakietu. Nieobsługiwana przyszła `schemaVersion` jest oznaczana jako wymagająca odświeżenia; aplikacja nie zgaduje migracji. Uszkodzony lub niekompletny pakiet nie jest używany.

Magazyn ma limit 6 pakietów, 32 MiB łącznie i 12 MiB na jeden pakiet. Sprzątanie używa LRU i nie usuwa jedynego istniejącego LKG tylko po to, aby zmieścić nowy pakiet.

## Status offline

Ekrany rozróżniają LIVE od `OFFLINE • LAST KNOWN GOOD`. Pokazywany jest czas snapshotu, czas pobrania i wiek danych. Stan źródeł z chwili snapshotu jest zachowany w manifeście. Offline nie przelicza starego zielonego statusu jako bieżącego; komunikat wprost przypomina, że brak nowych danych nie potwierdza bezpieczeństwa.

## Schronienia i lokalizacja

Po pobraniu pakietu pełny katalog schronień regionu działa po restarcie: wyszukiwanie i nearest shelter są liczone lokalnie. Przy lokalnym fallbacku bieżące współrzędne GPS nie są wysyłane do backendu i nie są zapisywane jako historia.

`Wokół mnie` może policzyć odległość wyłącznie do Eventów z geometrią zapisaną w pakiecie. Wynik ma timestamp pakietu i jawnie częściowe pokrycie. Brak geometrii nie jest interpretowany jako brak zagrożenia.

## Mapa

MapLibre nadal korzysta z OpenFreeMap jako podkładu sieciowego. Alpha.15 **nie udaje pełnego offline tilesetu**. Pakiet zapewnia lokalny overlay schronień (z lokalnym clusteringiem) i metadane warstw; jeżeli podkład bazowy nie jest dostępny, UI informuje o tym jawnie. Pełne pobieranie kafli wymaga osobnego etapu z decyzją o providerze/licencji/rozmiarach.

## Ukraina, NEPTUN i push

- Ukraina zachowuje własny cache i semantykę STALE; nie wpływa na Status Polski.
- NEPTUN pozostaje historycznym modułem OSINT i nie trafia do polskiego pakietu regionu.
- Operacje offline nie modyfikują kluczy ani preferencji push. Brak sieci nie uruchamia dodatkowej pętli rejestracji tokenu.

## CI / preview

Workflow `alpha15-preview.yml` uruchamia pełny backend + real PostGIS, restart bazy i procesu, pełne testy Fluttera, osobny kontrakt pakietów offline, NEPTUN safety contract, push contract, live checks oraz arm64-only preview APK:

- versionName: `0.1.0-alpha.15`
- versionCode: `2015`
- package: `pl.bezpiecznapolska.preview`
- artifact: `Bezpieczna_Polska_0.1.0-alpha.15-preview-arm64`

Produkcja, pełne offline tiles i hosting pozostają poza alpha.15.
