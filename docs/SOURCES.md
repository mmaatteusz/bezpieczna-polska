# Rejestr źródeł

Weryfikacja publicznych stron i stanu integracji: 21.09.2026. Brak API oznacza brak potwierdzonej dokumentacji; nie dowodzi, że nie istnieje interfejs wewnętrzny.

| Źródło | Właściciel i URL | Interfejs / stan | Autoryzacja, częstotliwość i ryzyko |
|---|---|---|---|
| RCB | RCB, https://www.gov.pl/web/rcb | HTML strony głównej i artykułów; adapter działa, lista niepełna | Publiczne; interwał 5 min; brak potwierdzonego SLA/limitu. Wysokie ryzyko zmiany selektorów. Brak automatycznego źródła zapasowego |
| RSO | MSWiA/TVP, https://komunikaty.tvp.pl/Info/Integration | Publiczny pełny eksport XML; adapter XML włączony | XML bez tokena; interwał 5 min; kontrola deklarowanej liczby rekordów i fail-closed przy zmianie struktury. Treści RSO nie są automatycznie uznawane za bezpośrednie zagrożenie |
| CERT Polska | NASK / CERT Polska, https://moje.cert.pl/komunikaty/ | Oficjalny RSS komunikatów bezpieczeństwa; adapter działa | Publiczne; recent publications, complete=false; komunikaty CYBER nie zmieniają automatycznie głównego statusu fizycznego |
| CSIRT GOV | CSIRT GOV, https://www.csirt.gov.pl/cer/rss | Oficjalna strona RSS działa, ale lista publicznych kanałów jest obecnie pusta; NOT_CONFIGURED | Nie importujemy raportów historycznych ani nie zgadujemy prywatnego feedu |
| PAA | PAA, https://www.gov.pl/web/paa/aktualnosci2 | Oficjalne komunikaty HTML; adapter działa. Pomiary stacji pozostają niepodłączone | Komunikat i pomiar są rozdzielone. Same wartości pomiarowe nigdy nie podnoszą automatycznie statusu; portal pomiarowy wymaga ponownej weryfikacji kontraktu |
| SG | Straż Graniczna, https://www.strazgraniczna.pl/pl/aktualnosci | Oficjalne Aktualności; adapter działa z filtrem operacyjnym | Publiczna lista RSS KGSG jest pusta. Importowane są wyłącznie zamknięcia, ograniczenia, kontrole i utrudnienia dotyczące przekraczania granicy; zwykłe newsy służbowe są odrzucane |
| POLICE | Policja, https://policja.pl/pol/rss | Oficjalny RSS „Aktualności”; adapter działa z konserwatywnym filtrem zdarzeń | Publiczne; recent publications, complete=false. Zatrzymania, kradzieże, odzyskane auta, rutynowy przemyt, statystyki i PR są odrzucane. Brak geokodowania tekstu |
| PSP_INCIDENTS | KG PSP, https://www.gov.pl/web/kgpsp/aktualnosci | Stabilny oficjalny HTML centralnych Aktualności; adapter działa z konserwatywnym filtrem zdarzeń | Nie znaleziono zweryfikowanego krajowego live API/RSS incydentów. Recent publications, complete=false; agregaty statystyczne „Interwencje PSP” nie są traktowane jako bieżące Eventy |
| Stopnie alarmowe | RCB, https://www.gov.pl/web/rcb/stopnie-alarmowe2 | Adapter HTML działa; obsługuje PHYSICAL/CRP i wiele równoległych zakresów | Brak publicznego kontraktu API; parser waliduje daty i zakresy, a awaria zachowuje ostatnią poprawną kopię |
| Schronienie | PSP / dane.gov.pl, https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce | Pełny import działa, PostGIS/bbox/clustering/offline cache | Runner GitHub otrzymuje 403 z serwera PSP; produkcja korzysta z last-known-good do czasu potwierdzenia niezależnego oficjalnego fallbacku |
| Ukraina | alerts.in.ua, https://devs.alerts.in.ua/ | Dokumentacja dostawcy, adapter niezaimplementowany | Nie traktować agregatora jako ukraińskiego organu państwowego. Token, licencja i pochodzenie danych wymagają sprawdzenia |

RSO: https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml — adres udokumentowany przez operatora; 0 oznacza pełny eksport. Nie jest to nieudokumentowany endpoint wymyślony przez aplikację.

Teksty gov.pl: warunki portalu i oznaczenia CC BY-SA 4.0 z wyjątkami trzeba potwierdzić dla redystrybucji produkcyjnej. Nie dołączono zdjęć. Fixture'y to fragmenty publicznych stron do testów kontraktu, nie bieżące dane w telefonie. RSO: sam publiczny dostęp nie rozstrzyga licencji redystrybucji.

Dla nieaktywnych adapterów nie określono zmyślonych limitów, interfejsów ani źródeł zapasowych. Pozostają NOT_CONFIGURED. Pobranie HTML nie oznacza pełnego pokrycia kategorii; complete=false blokuje zieloną ocenę przy niepełnej obserwacji.
