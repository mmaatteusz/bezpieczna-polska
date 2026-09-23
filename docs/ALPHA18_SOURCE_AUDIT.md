# Alpha.18 — weryfikacja kompletności źródeł (2026-09-23)

Ten dokument opisuje zweryfikowane możliwości integracji. Status źródła w aplikacji jest rozstrzygający w chwili odczytu; wykaz adresów nie jest dowodem pełnego pokrycia operacyjnego.

## WCZK (16 województw)

Rejestr 16 urzędów: `backend/src/wczk-registry.ts`. Wyniki odkrywania oficjalnych stron dla każdego województwa: `docs/validation/wczk/discovery.json`. Działający, odrębny adapter: `WCZK-18` (Podkarpackie), z niepełnym pokryciem. Dla pozostałych 15 regionów nie potwierdzono niezależnego, stabilnego kontraktu danych i pozostają niepodłączone. To nie oznacza, że urzędy nie publikują ostrzeżeń.

Kujawsko-pomorski urząd wyjaśnia, że regionalne komunikaty RSO generuje WCZK i publikuje je również urząd. Nie liczymy tego samego kanału jako drugiego źródła WCZK: https://www.gov.pl/web/uw-kujawsko-pomorski/regionalny-system-ostrzegania

Śląski urząd publikuje osobną sekcję „Ostrzeżenia i Raporty WCZK”: https://www.katowice.uw.gov.pl/usluga/ostrzezenia-i-raporty-wczk . Ponowna próba odczytu pełnych stron zwróciła 502/timeout, zatem nie potwierdzono struktury komunikatu, czasu obowiązywania ani stabilności. Nie uruchamiać adaptera z samych fragmentów indeksu wyszukiwarki.

## PAA

PAA odsyła do https://monitoring.paa.gov.pl/maps-portal/ jako miejsca bieżących pomiarów. Portal ma także widok tekstowy `/maps-portal/measurements`; w sprawdzonym interfejsie widoczny był opis sieci, bez udokumentowanego eksportu stacji z jednostką, czasem i współrzędnymi. Nie ustalono bezpiecznego, oficjalnego kontraktu API. Nie traktować interfejsów wewnętrznych aplikacji mapowej ani pomiaru jako ostrzeżenia. Oficjalny opis PAA: https://www.gov.pl/web/paa/monitoring-radiacyjny-kraju--krotki-film-staly-nadzor-paa

## CSIRT GOV

Oficjalna strona https://www.csirt.gov.pl/cer/rss opisuje RSS, ale lista kanałów RSS nie zawierała działającego kanału CSIRT GOV. Parser `parseCsirtGovRssLanding` ma zachować brak konfiguracji. Publikacje redakcyjne nie stanowią automatycznie kanału bieżących ostrzeżeń.

## Granice, Policja, PSP

Izba Administracji Skarbowej w Białymstoku publikuje opis usługi SOAP/WSDL z czasami oczekiwania: https://granica.gov.pl/nowa_usluga.php . To odrębny wydawca i dane o kolejce, nie kanał zamknięć/przywróceń Straży Granicznej. Nie podnosić na tej podstawie `SG.complete`. Ewentualna integracja wymaga osobnego modelu, weryfikacji kontraktu HTTPS i czasu aktualizacji.

KG PSP udostępnia dzienne zestawienia w podziale na województwa oraz archiwum interwencji: https://www.gov.pl/web/kgpsp/interwencje-polska i https://www.gov.pl/web/kgpsp/interwencje-psp . Nie ma w nich lokalizacji i cyklu życia każdego bieżącego zdarzenia; nie tworzyć z nich punktów na mapie.

Policyjna KMZB prezentuje zgłoszenia z osobnym etapem weryfikacji: https://policja.pl/pol/aktualnosci/242812%2CKrajowa-Mapa-Zagrozen-Bezpieczenstwa-TY-zglaszasz-MY-dzialamy.html . To mapa zgłoszeń społecznych, nie operacyjna mapa wszystkich interwencji. Zachować częściowy charakter obecnego źródła Policji.

## Ukraina i mapa offline

CI przekazuje `secrets.UKRAINE_ALARM_API_KEY` do live smoke. Log przebiegu z 2026-09-23 dla alpha.18 wskazał `NOT_CONFIGURED_UA_API_KEY_MISSING`: test kontraktu przeszedł, lecz uwierzytelniony live smoke nie przeszedł. Właściciel repo musi ustawić sekret o dokładnej nazwie `UKRAINE_ALARM_API_KEY`, bez wpisywania klucza do kodu.

Użyta wersja `maplibre_gl: 0.27.1` eksponuje publiczne funkcje `downloadOfflineRegion`, `getOfflineRegionStatus`, `pauseOfflineRegionDownload` i `deleteOfflineRegion` na Androidzie i iOS: https://pub.dev/documentation/maplibre_gl/latest/maplibre_gl/ . Przed włączeniem trzeba ograniczyć liczbę kafli i rozmiar, zapewnić aktualizację z poprzednim działającym regionem oraz oddzielne wersje danych bezpieczeństwa i podkładu.
