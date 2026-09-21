# Etap CYBER — CERT Polska / CSIRT GOV

Stan źródeł zweryfikowany 21.09.2026. Ten dokument opisuje faktycznie podłączone kanały, a nie planowane możliwości.

## CERT Polska

Aktywne źródło: `https://moje.cert.pl/advisory_feed/advisory/feed/`.

Adres został wykryty bezpośrednio w oficjalnej stronie `https://moje.cert.pl/komunikaty/` jako `<link rel="alternate" type="application/rss+xml">` i sprawdzony z GitHub Actions. Feed zwraca RSS 2.0 z bieżącymi komunikatami bezpieczeństwa.

Adapter `CERT`:
- waliduje RSS 2.0 i kanał moje.cert.pl;
- przyjmuje wyłącznie linki `https://moje.cert.pl/komunikaty/<rok>/<numer>/<slug>/`;
- normalizuje komunikaty do wspólnego `Event` z `eventType=CYBER`;
- odrzuca raporty miesięczne i wydarzenia jako niebędące bieżącymi ostrzeżeniami;
- nie wymyśla czasu wygaśnięcia, geometrii ani zasięgu terytorialnego;
- ustawia `officialWarning=false`, więc komunikat cyber nie zmienia automatycznie głównego statusu zagrożenia fizycznego;
- klasyfikuje severity wyłącznie pomocniczo dla prezentacji sekcji cyber;
- zachowuje last-known-good przez istniejący Store/sourceHealth.

RSS jest źródłem ostatnich publikacji, dlatego `complete=false` i `coverage=RECENT_PUBLICATIONS`. Brak elementu w feedzie nie dowodzi, że zagrożenie przestało istnieć.

## CSIRT GOV

Oficjalna strona usługi RSS: `https://www.csirt.gov.pl/cer/rss`.

Weryfikacja z GitHub Actions wykazała, że strona działa, ale sekcja „Lista” zawiera pustą listę `<ul></ul>`. Sprawdzone typowe adresy `rss.xml`, `feed`, `feed.xml` itp. zwracają HTML strony albo 404, nie kanał RSS.

Dlatego `CSIRT_GOV` jest jawnie:
- `enabled=false`;
- `NOT_CONFIGURED`;
- `implementation=RSS_CHANNEL_LIST_EMPTY`.

Nie importujemy raportów historycznych ani strony „Publikacje” jako bieżącego feedu ostrzeżeń. Gdy oficjalna lista RSS zacznie publikować kanał, live contract check celowo zgłosi zmianę kontraktu i integracja będzie mogła zostać aktywowana po weryfikacji.

## Korelacja CERT ↔ CSIRT GOV

Silnik korelacji jest przygotowany na oba źródła, ale pozostaje konserwatywny:
- wymagane są różne źródła;
- komunikaty muszą być typu `CYBER`;
- czas publikacji nie może różnić się o więcej niż 72 h;
- jeśli występują identyfikatory CVE, musi istnieć wspólny CVE;
- bez CVE wymagany jest praktycznie identyczny tytuł albo bardzo wysokie podobieństwo treści;
- brak wystarczających danych oznacza brak scalenia.

Oryginalne Eventy i rewizje są zachowywane.

## UI

- sekcja „Cyberbezpieczeństwo” na ekranie Status pokazuje ostatnie komunikaty cyber;
- Alert Center obsługuje kategorię `Cyber` i źródła CERT / CSIRT_GOV;
- dane są dostępne offline w istniejącym cache snapshotu;
- STALE/sourceHealth działa tak samo jak dla pozostałych źródeł;
- brak geometrii oznacza brak punktów cyber na mapie.

## Live validation

Workflow alpha.8 sprawdza:
- backend + PostGIS;
- Flutter analyze/test;
- Android arm64 APK;
- dotychczasowe live WCZK i PAA;
- żywy RSS CERT Polska;
- oficjalną stronę RSS CSIRT GOV i oczekiwany brak publicznych kanałów.

Moduł nie omija zabezpieczeń, nie korzysta z prywatnych ostrzeżeń CSIRT GOV i nie interpretuje raportów historycznych jako bieżących alarmów.
