# Etap Straż Graniczna / granice — alpha.9

Stan źródeł zweryfikowany 21.09.2026.

## Oficjalne źródła

Główne źródło: `https://www.strazgraniczna.pl/pl/aktualnosci`.

Oficjalna strona RSS KGSG `https://www.strazgraniczna.pl/pl/rss` działa, ale sekcja „Lista” jest obecnie pusta. Typowe adresy `rss.xml`, `feed`, `feed.xml` i warianty kanału Aktualności nie zwracają kanału XML z komunikatami. Z tego powodu moduł nie udaje działającego RSS i nie zgaduje prywatnego endpointu.

## Zakres integracji

Adapter `SG` skanuje ograniczone okno najnowszych publikacji z oficjalnej strony Aktualności oraz ponownie sprawdza kilka wcześniej zapisanych, niezakończonych komunikatów SG.

Do aplikacji trafiają tylko publikacje dotyczące operacyjnej dostępności granicy, m.in.:
- utrudnień na przejściach granicznych,
- czasowego wstrzymania ruchu lub odpraw,
- zamknięcia / nieczynności przejścia,
- ograniczeń ruchu lub wjazdu,
- czasowych kontroli granicznych, gdy publikacja opisuje ich wpływ na przekraczanie granicy,
- przywrócenia ruchu / wznowienia odpraw.

Zwykłe newsy służbowe nie są importowane jako alerty graniczne. Przykładowo zatrzymanie osoby, odzyskanie samochodu, przemyt czy statystyka kontroli na przejściu granicznym nie wystarcza do utworzenia `BORDER`.

## Model danych i bezpieczeństwo semantyczne

Komunikaty są normalizowane do wspólnego `Event`:
- `eventType=BORDER`,
- `verification=CONFIRMED`,
- źródło Tier 1: Straż Graniczna,
- bez wymyślonej geometrii,
- bez wymyślonego czasu końca,
- data publikacji zachowuje precyzję dnia, jeśli źródło nie podaje godziny,
- region przypisywany jest tylko wtedy, gdy publikacja jawnie wskazuje województwo,
- tytuł publikacji jest zachowany jako `locationText` zamiast geokodowania z tekstu.

Operacyjny komunikat SG ma `officialWarning=false`. Utrudnienie graniczne samo w sobie nie zmienia głównego statusu zagrożenia fizycznego Polski lub regionu.

Jeżeli źródło jednoznacznie informuje o przywróceniu ruchu lub wznowieniu odpraw, komunikat może otrzymać `lifecycle=ENDED`. W pozostałych przypadkach bez wiarygodnego przedziału ważności lifecycle pozostaje `UNKNOWN`, zamiast utrzymywać fikcyjny stan ACTIVE bez końca.

## UI

- osobna sekcja „Granice • Straż Graniczna” na ekranie Status,
- kategoria `Granica` w Alert Center,
- filtr źródła `SG`,
- link do oficjalnych Aktualności SG,
- dane są przechowywane w istniejącym cache snapshotu i podlegają oznaczeniu STALE/sourceHealth,
- brak punktów na mapie, jeśli źródło nie podało rzeczywistej geometrii.

## sourceHealth

Źródło korzysta z ograniczonego archiwum najnowszych publikacji, dlatego:
- `complete=false`,
- `coverage=RECENT_PUBLICATIONS`,
- brak nowego komunikatu nie jest dowodem braku utrudnień,
- awaria synchronizacji zachowuje last-known-good,
- stan SG nie jest używany jako dowód pełnego pokrycia głównego statusu bezpieczeństwa.

## Live validation

Workflow alpha.9 sprawdza:
- backend + PostGIS,
- testy parsera i false-positive,
- Flutter analyze/test,
- Android arm64 APK,
- istniejące live checki WCZK, PAA, CERT/CSIRT,
- żywą stronę Aktualności SG i parser aktualnych artykułów.

Moduł nie importuje wszystkich wiadomości SG i nie próbuje automatycznie oceniać zagrożenia na podstawie działalności operacyjnej służby.
