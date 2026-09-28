# Rejestr źródeł

Stan kontraktów źródeł: 27.09.2026. Brak publicznego API oznacza brak potwierdzonego kontraktu do użycia przez aplikację; nie dowodzi, że nie istnieje interfejs wewnętrzny.

## Kontrakt jakości

Każde źródło ma jawny `sourceClass` oraz `absenceSemantics`.

- `STATUS` — źródło może wnosić oficjalne ostrzeżenia do głównego statusu.
- `CONTEXT` — oficjalne informacje pomocnicze; awaria nie blokuje głównego statusu.
- `REFERENCE` — dane referencyjne lub pomiarowe, np. schronienia i stacje PAA.
- `SITUATIONAL` — oddzielna świadomość sytuacyjna, np. NEPTUN/UA.
- `AUTHORITATIVE_EMPTY_SET` — poprawny pusty wynik jest częścią zweryfikowanego kontraktu bieżącego stanu.
- `NOT_PROVABLE` — brak wpisu nie jest dowodem braku zagrożenia.

Wzorzec jakości stanowią `IMGW_METEO` i `IMGW_HYDRO`: bieżący oficjalny feed, jawna semantyka pustego wyniku, `complete=true`, `coverage=ACTIVE_WARNINGS` oraz fail-closed przy zmianie kontraktu.

| Źródło | Właściciel i URL | Interfejs / stan | Autoryzacja, częstotliwość i ryzyko |
|---|---|---|---|
| RCB | RCB, https://www.gov.pl/web/rcb | HTML strony głównej i artykułów; adapter działa, lista niepełna | Publiczne; interwał 5 min; brak potwierdzonego SLA/limitu. Wysokie ryzyko zmiany selektorów. Brak automatycznego źródła zapasowego |
| RSO | MSWiA/TVP, https://komunikaty.tvp.pl/Info/Integration | Publiczny pełny eksport XML; adapter XML włączony | XML bez tokena; interwał 5 min; kontrola deklarowanej liczby rekordów i fail-closed przy zmianie struktury. Treści RSO nie są automatycznie uznawane za bezpośrednie zagrożenie |
| WCZK | Wojewódzkie centra zarządzania kryzysowego; rejestr źródeł w adapterach | Rejestr 16 centrów, niezależny adapter Podkarpackiego i deduplikacja RCB–RSO–WCZK | Nie wszystkie województwa mają niezależny pełny adapter; obecności publikacji RSO nie należy mylić z pełnym pokryciem WCZK |
| CERT Polska | NASK / CERT Polska, https://moje.cert.pl/komunikaty/ | Oficjalny RSS komunikatów bezpieczeństwa; adapter działa | Publiczne; recent publications, complete=false; komunikaty CYBER nie zmieniają automatycznie głównego statusu fizycznego |
| CSIRT GOV | CSIRT GOV, https://www.csirt.gov.pl/cer/rss | Oficjalna strona RSS działa, ale lista publicznych kanałów jest obecnie pusta; NOT_CONFIGURED | Nie importujemy raportów historycznych ani nie zgadujemy prywatnego feedu |
| IMGW_METEO / IMGW_HYDRO | IMGW-PIB, https://danepubliczne.imgw.pl/apiinfo | Oficjalne publiczne JSON API ostrzeżeń meteorologicznych i hydrologicznych; dwa niezależne adaptery ACTIVE_WARNINGS | Interwał min. 5 min. TERYT/obszary mapowane do województw, bez zgadywania geometrii. Dokładna odpowiedź 404 z komunikatem No products were found jest pustym zbiorem; każdy inny błąd fail-closed. Warunki IMGW wymagają wskazania źródła i informacji o przetworzeniu danych |
| PAA | PAA, https://www.gov.pl/web/paa/aktualnosci2 + https://monitoring.paa.gov.pl/maps-portal/ | Oficjalne komunikaty HTML oraz osobny live adapter WFS/GeoJSON dla sieci PMS | Komunikat i pomiar są rozdzielone. Pomiary mają `MEASUREMENT_NETWORK` i nie tworzą ani nie odwołują alarmu; komunikaty PAA pozostają `NOT_PROVABLE` jako lista publikacji |
| SG | Straż Graniczna, https://www.strazgraniczna.pl/pl/aktualnosci | Oficjalne Aktualności; adapter działa z filtrem operacyjnym | Publiczna lista RSS KGSG jest pusta. Importowane są wyłącznie zamknięcia, ograniczenia, kontrole i utrudnienia dotyczące przekraczania granicy; zwykłe newsy służbowe są odrzucane |
| POLICE | Policja, https://policja.pl/pol/rss | Oficjalny RSS „Aktualności”; adapter działa z konserwatywnym filtrem zdarzeń | Publiczne; recent publications, complete=false. Zatrzymania, kradzieże, odzyskane auta, rutynowy przemyt, statystyki i PR są odrzucane. Brak geokodowania tekstu |
| PSP_INCIDENTS | KG PSP, https://www.gov.pl/web/kgpsp/aktualnosci | Stabilny oficjalny HTML centralnych Aktualności; adapter działa z konserwatywnym filtrem zdarzeń | Nie znaleziono zweryfikowanego krajowego live API/RSS incydentów. Recent publications, complete=false; agregaty statystyczne „Interwencje PSP” nie są traktowane jako bieżące Eventy |
| Stopnie alarmowe | RCB, https://www.gov.pl/web/rcb/stopnie-alarmowe2 | Adapter HTML działa; obsługuje PHYSICAL/CRP i wiele równoległych zakresów | Brak publicznego kontraktu API; parser waliduje daty i zakresy, a awaria zachowuje ostatnią poprawną kopię |
| Schronienie | PSP / dane.gov.pl, https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce | Import, PostGIS/bbox/clustering i pakiety offline regionu w kodzie | Przy 403 na bieżącym eksporcie istnieje fallback do starszego oficjalnego zasobu dane.gov.pl, ale nie jest to niezależny drugi wydawca. Last-known-good jest widoczne jako stare dane, nie jako live |
| Ukraina | UkraineAlarm, https://api.ukrainealarm.com/ | ✅ produkcyjny live przez oficjalne API v3; jeden uwierzytelniony `/api/v3/alerts` na cykl, worker 90 s, fail-closed i jawny health | `UKRAINE_ALARM_API_KEY` jest wyłącznie sekretem backendu. Warstwa UA jest sytuacyjna, nie wpływa na Status Polski; zakończenie alarmu jest wyznaczane przez zniknięcie z bieżącego feedu bez wymyślania dokładnego czasu końca |

RSO: https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml — adres udokumentowany przez operatora; 0 oznacza pełny eksport. Nie jest to nieudokumentowany endpoint wymyślony przez aplikację.

Teksty gov.pl: warunki portalu i oznaczenia CC BY-SA 4.0 z wyjątkami trzeba potwierdzić dla redystrybucji produkcyjnej. Nie dołączono zdjęć. Fixture'y to fragmenty publicznych stron do testów kontraktu, nie bieżące dane w telefonie. RSO: sam publiczny dostęp nie rozstrzyga licencji redystrybucji.

Dla nieaktywnych adapterów nie określono zmyślonych limitów, interfejsów ani źródeł zapasowych. Pozostają NOT_CONFIGURED. Pobranie HTML nie oznacza pełnego pokrycia kategorii; complete=false blokuje zieloną ocenę przy niepełnej obserwacji.
