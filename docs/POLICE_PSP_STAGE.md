# ALPHA.10 — Policja i PSP: istotne zdarzenia

Stan: branch `stage/police-psp-incidents`, baza `stage/sg-border`.

## Zweryfikowane źródła

### POLICE

Źródło podstawowe: oficjalny RSS Policji „Aktualności”:

`https://policja.pl/dokumenty/rss/1-rss-1.rss`

RSS jest preferowany zamiast scrapowania listy HTML. Adapter traktuje go jako archiwum/recent publications, nie kompletną listę aktywnych zagrożeń.

### PSP_INCIDENTS

Źródło podstawowe: centralne Aktualności Komendy Głównej PSP:

`https://www.gov.pl/web/kgpsp/aktualnosci`

W czasie researchu nie potwierdzono stabilnego krajowego publicznego live API ani RSS zawierającego pojedyncze incydenty PSP. Oficjalne zestawienia interwencji są agregatami/statystyką, więc nie są mapowane na Eventy. Adapter używa stabilnego HTML gov.pl, fail-closed przy zmianie kontraktu.

## Filtr sytuacyjny

Importowane są tylko zdarzenia o realnym znaczeniu dla świadomości sytuacyjnej: duże pożary i pożary obiektów/infrastruktury, eksplozje, HAZMAT, katastrofy/rozległe ratownictwo, masowe ewakuacje, poważne blokady kluczowych tras oraz poważne zdarzenia bezpieczeństwa publicznego.

Odrzucane są m.in. zwykłe zatrzymania, kradzieże, odzyskane auta, rutynowy przemyt, narkotyki bez wpływu sytuacyjnego, statystyki, konkursy, uroczystości, szkolenia, ćwiczenia, kampanie, materiały historyczne i PR.

## Semantyka bezpieczeństwa

- `POLICE` i `PSP_INCIDENTS` są osobnymi źródłami.
- `PSP_INCIDENTS` nie zastępuje `SHELTERS` / katalogu schronień.
- Publikacje służb mają `officialWarning=false`; nie tworzą automatycznie `ACTIVE_DANGER` dla regionu.
- Brak elementów w recent-publications nie oznacza braku zdarzeń.
- `complete=false` i `coverage=RECENT_PUBLICATIONS`.
- Brak współrzędnych w źródle oznacza `geometry=null`, `latitude=null`, `longitude=null`.
- Data bez godziny pozostaje `publicationDate`; aplikacja nie tworzy północy jako fałszywego `publishedAt`.
- Korelacja z RCB/RSO/WCZK jest complete-link i zachowuje wszystkie Eventy, URL-e oraz rewizje; liczba źródeł nie zmienia automatycznie `verification`.
- Błąd kontraktu źródła ustawia BROKEN, zachowując last-known-good.

## Typy

Wspólny model wykorzystuje `FIRE`, a dla brakujących równoważników dodaje:
`EXPLOSION`, `HAZMAT`, `RESCUE`, `PUBLIC_SAFETY`.

## UI

Bez redesignu. Status zawiera sekcję „Zdarzenia służb”. Alert Center ma źródła Policja/PSP i kategorie Pożar, Wybuch, Ratownictwo, Zagrożenie chemiczne oraz Bezpieczeństwo publiczne. Mapa nie tworzy punktów z tekstu lokalizacji.

## Znane ograniczenia

Centralne publikacje Policji i KG PSP nie są pełnym operacyjnym rejestrem wszystkich interwencji. Pokrycie jest jawnie częściowe. Rozszerzanie o komendy wojewódzkie/powiatowe powinno następować wyłącznie po osobnej weryfikacji kontraktów źródeł, bez udawania niezależnego potwierdzenia tam, gdzie treść jest tylko republika­cją.

Następny etap roadmapy: alpha.11 — obserwowane lokalizacje i „wokół mnie”.
