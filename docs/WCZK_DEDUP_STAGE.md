# WCZK i korelacja — alpha.6

Baza: `stage/quality-pass`, commit `76f6bfc0324e7a20097ec235fad4beba07b3215a`, PR #5 (draft, nie zmergowany).
Drzewo bazy: `5735818ad50d54c95f69ed912c7d91032a56a5f5`. Nowy branch: `stage/wczk-dedup`.
Lokalny odczyt bazy zweryfikowano po hashach Git; bazowe testy: 66 PASS, 2 PostGIS pominięte lokalnie.
CI bazy: RCB i PSP PASS na HEAD; preview alpha.5 PASS na rodzicu `a16ddac` (HEAD usuwa tylko tymczasowy workflow).

## Źródła

Katalog urzędów: https://www.gov.pl/web/gov/uw . Wyniki odczytów wszystkich 16 urzędów,
przekierowania i odkryte linki: `docs/validation/wczk/discovery.json` (2026-09-21).
Nieudany odczyt w tym środowisku nie dowodzi, że urząd nie ma źródła; oznacza brak
zweryfikowanej integracji. Nie zgadywano adresów RSS/API.

| Województwo | Osobna integracja WCZK | Ustalenie |
|---|---|---|
| Kujawsko-pomorskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Oficjalny widget ostrzeżeń jest kanałem RSO; brak zweryfikowanego osobnego kanału |
| Podkarpackie | IMPLEMENTED | Dedykowany HTML ostrzeżeń WCZK, pojedyncze żądanie co 15 min |
| Dolnośląskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Portal gov.pl, widget ostrzeżeń; osobny feed niezweryfikowany |
| Lubelskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Odczyt strony głównej bez odkrytego kanału ostrzeżeń |
| Lubuskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Błąd odczytu 502 podczas weryfikacji |
| Łódzkie | NOT_IMPLEMENTED / NOT_CONFIGURED | Portal gov.pl, odsyłacz do zarządzania kryzysowego |
| Małopolskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Błąd odczytu 502 podczas weryfikacji |
| Mazowieckie | NOT_IMPLEMENTED / NOT_CONFIGURED | Portal gov.pl, widget ostrzeżeń |
| Opolskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Znaleziono pojedyncze artykuły; kanał zbiorczy niezweryfikowany |
| Podlaskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Oficjalny odsyłacz do RSO i działu ostrzeżeń; brak zweryfikowanego osobnego kontraktu |
| Pomorskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Timeout odczytu podczas weryfikacji |
| Śląskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Oficjalny dział WCZK znaleziony, odczyt hosta 502 |
| Świętokrzyskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Portal gov.pl, sekcja ostrzeżeń |
| Warmińsko-mazurskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Oficjalna strona RSO i widget ostrzeżeń |
| Wielkopolskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Odczyt strony głównej bez zweryfikowanego feedu WCZK |
| Zachodniopomorskie | NOT_IMPLEMENTED / NOT_CONFIGURED | Błąd odczytu 502 podczas weryfikacji |

Kujawsko-pomorskie pozostaje priorytetem, ale nie tworzymy fikcyjnego drugiego źródła.
https://www.gov.pl/web/uw-kujawsko-pomorski/regionalny-system-ostrzegania wyjaśnia,
że regionalne komunikaty RSO generują WCZK. Strona główna osadza komponent `rso`
z `voivodeship="kujawsko-pomorskie"`. Istniejący adapter RSO zachowano.
Odrębna niezależna integracja tego województwa NIE jest ukończona.

Podkarpackie: https://rzeszow.uw.gov.pl/wczk/ostrzezenia . Brak reklamowanego
RSS/XML/JSON w pobranej stronie. HTML ma odrębne kontenery komunikatów, identyfikatory
oraz podpisane pola Ważność/Obszar. Zmiana kontraktu, nierozpoznany obszar, pusta
odpowiedź, niejednoznaczny czas DST lub duplikat ID przerywa całą synchronizację.
Ostatnia poprawna kopia pozostaje w bazie, źródło otrzymuje BROKEN (odpowiednik DOWN).
Nie traktujemy pustej strony jako odwołania alertów.

Daty publikacji nie występują w tym wykazie: `publishedAt=null`. `validFrom` jest
przeliczany z Europe/Warsaw; „do odwołania” pozostawia `validTo=null` i nie udaje
terminowego aktywnego ostrzeżenia w StatusEngine. Opis obszaru jest zachowany w
`locationText`; województwa rozpoznawane tylko po pełnych nazwach w tym polu.
SVG mapy nie jest geometrią WGS84: `geometry`, `latitude`, `longitude` pozostają null.
Kontrakt nie nadaje automatycznie poziomu CRITICAL. Nowe nieobsługiwane formaty
wymagają nowej fixture i jawnej aktualizacji adaptera.

## Korelacja

Bez LLM. `canCorrelate` wymaga różnego źródła, identycznego zbioru znanych województw,
zgodnego typu i jednego rozpoznanego rodzaju zagrożenia, nakładających się okresów,
różnicy początku do 12 h oraz wysokiego podobieństwa zbiorów słów. Przy jednakowym
pełnym `locationText` i obszarze EXACT w obu źródłach próg wynosi 0.78. W pozostałych
przypadkach wymagana jest identyczna znormalizowana treść wraz z tytułem. Są to techniczne progi testowalne,
nie procenty wiarygodności i nie są prezentowane użytkownikowi. Różniące się liczby,
obszary, ćwiczenia, złożone wielozagrożeniowe komunikaty i brak czasu blokują dopasowanie.

Nowy komunikat musi pasować do KAŻDEGO członka dokładnie jednej grupy. Nie ma scalania
przechodniego ani automatycznego łączenia dwóch istniejących grup. Sortowanie po ID
zapewnia powtarzalność dla tej samej partii. Celowo zachowywana jest historia kolejnych
partii: wynik nie jest obietnicą globalnej niezależności od kolejności napływu źródeł.
Niepełne dane RCB (sama data publikacji bez czasu i bez validFrom) mogą pozostać osobno.
To świadomy koszt ograniczania błędnych połączeń.

`incident_revisions` zawiera trwałe ID, członków, wersje źródłowych eventów, wybrany
komunikat, źródła i kolejne rewizje. Wszystkie oryginalne Eventy pozostają w
`event_revisions`. Zmiany źródła i grupy zapisywane są w jednej transakcji.
Przedłużenie, zmiana obszaru, zakończenie i sprostowanie nie usuwają członkostwa ani
poprzednich rewizji. Różnice są jawne. Jedno źródło nie może zakończyć ostrzeżeń innych
wydawców. Ponowna synchronizacja bez zmiany treści nie tworzy nowych rewizji.

## API i aplikacja

`/status` i snapshot dodają `supportingIncidents`, `incidentCount` i reprezentanta
na każdą grupę. Ocena zagrożenia nadal wykorzystuje oryginalne, kwalifikujące się Eventy;
liczba źródeł nie mnoży poziomu zagrożenia. Nie promujemy RSO UNVERIFIED do CONFIRMED.
WCZK NOT_CONFIGURED/STALE/BROKEN oznacza brak pokrycia, a nie brak zagrożenia.
Diagnostyka danego WCZK dotyczy jego województwa oraz oceny ogólnopolskiej.

Snapshot zachowuje `events` i dodaje `incidents` z oryginalnymi `reports` tego samego
modelu Event. Starsze snapshoty aplikacja nadal czyta. Alert Center grupuje karty,
filtruje po RCB/RSO/WCZK, przeszukuje treść wszystkich członków. Szczegóły pokazują
każdy komunikat, jego publikację, ważność, obszar, link i wspólną historię źródłową.
Etykieta „Komunikaty z N źródeł” nie oznacza N niezależnych dowodów: WCZK i RSO mogą
rozpowszechniać tę samą informację IMGW. Nie stosujemy procentów wiarygodności.

Nowe odczyty: `/v1/incidents/:id/timeline`, `/v1/incidents/:id/history`.
Istniejący timeline eventów pozostaje dostępny. Warstwa events GeoJSON przyjmuje
`source=WCZK`; bez rzeczywistej geometrii nie produkuje punktu. WCZK pozostaje
wyłączoną warstwą w rejestrze mapy. Nie zmieniono renderera MapLibre.

Preview alpha.6 ma Developer Settings do wskazania backendu, tak jak alpha.5.
Nie wdraża automatycznie serwera ani nie zawiera fikcyjnych alertów produkcyjnych.
Brak ustawionego API_BASE_URL jest jawny i nie oznacza działającej usługi na telefonie.
Po etapie zatrzymujemy rozwój: bez PAA/CERT/SG/Ukrainy/NEPTUN/push i bez merge.
