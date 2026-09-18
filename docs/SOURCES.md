# Rejestr źródeł

Weryfikacja publicznych stron: 18.09.2026. Brak API oznacza brak potwierdzonej dokumentacji; nie dowodzi, że nie istnieje interfejs wewnętrzny.

| Źródło | Właściciel i URL | Interfejs / stan | Autoryzacja, częstotliwość i ryzyko |
|---|---|---|---|
| RCB | RCB, https://www.gov.pl/web/rcb | HTML strony głównej i artykułów; adapter działa, lista niepełna | Publiczne; interwał 5 min; brak potwierdzonego SLA/limitu. Wysokie ryzyko zmiany selektorów. Brak automatycznego źródła zapasowego |
| RSO | MSWiA/TVP, https://komunikaty.tvp.pl/Info/Integration | Publiczny XML/JSON; adapter XML działa | XML bez tokena; CAP wymaga tokena operatora. Interwał 5 min; limit nieudokumentowany. Kontrola liczby rekordów. Umiarkowane ryzyko zmian |
| CERT Polska | NASK, https://cert.pl/ | Adapter niezaimplementowany | Limit, format dystrybucji i licencja do weryfikacji |
| PAA | PAA, https://www.gov.pl/web/paa | Adapter niezaimplementowany | Nie interpretować pojedynczych skoków czujnika jako alarmu |
| SG | Straż Graniczna, https://www.strazgraniczna.pl/pl/rss | Publiczna strona RSS; adapter niezaimplementowany | Kwalifikacja znaczenia i licencja do weryfikacji |
| Stopnie alarmowe | RCB, https://www.gov.pl/web/rcb/stopnie-alarmowe2 | Adapter niezaimplementowany | Brak potwierdzonego API; wymaga dat i zakresu każdej decyzji |
| Schronienie | PSP, https://gdziesieukryc.pl/ | Brak zaimportowanego zbioru i potwierdzonego kontraktu API | Warunki ponownego użycia, daty weryfikacji i dostępność obiektów do potwierdzenia |
| Ukraina | alerts.in.ua, https://devs.alerts.in.ua/ | Dokumentacja dostawcy, adapter niezaimplementowany | Nie traktować agregatora jako ukraińskiego organu państwowego. Token, licencja i pochodzenie danych wymagają sprawdzenia |

RSO: https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml — adres udokumentowany przez operatora; 0 oznacza pełny eksport. Nie jest to nieudokumentowany endpoint wymyślony przez aplikację.

Teksty gov.pl: warunki portalu i oznaczenia CC BY-SA 4.0 z wyjątkami trzeba potwierdzić dla redystrybucji produkcyjnej. Nie dołączono zdjęć. Fixture'y to fragmenty publicznych stron do testów kontraktu, nie bieżące dane w telefonie. RSO: sam publiczny dostęp nie rozstrzyga licencji redystrybucji.

Dla nieaktywnych adapterów nie określono zmyślonych limitów, interfejsów ani źródeł zapasowych. Wszystkie pozostają NOT_CONFIGURED. Pobranie HTML nie oznacza pełnego pokrycia kategorii; complete=false blokuje zieloną ocenę przy niepełnej obserwacji.
