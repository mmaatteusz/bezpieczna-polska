# PAA — komunikaty i pomiary

Baza: stage/wczk-dedup, 4265b4873f3e7d64670cb7b931654026c9d2a646, PR #6 (bez merge).
Zweryfikowane zielone workflowy bazy: 35590901741 (PSP), 35590901780 (RCB), 35590897522 (preview).

## Oficjalne źródła i granice integracji

- https://www.gov.pl/web/paa/aktualnosci2 — dostępny oficjalny HTML, trzy strony publikacji; odnośniki paginacji pochodzą z HTML. Nie znaleziono zweryfikowanego API/feedu.
- https://www.gov.pl/web/paa/sytuacja-radiacyjna-w-normie--nie-ma-zagrozenia — rzeczywisty komunikat z 08.05.2026, fixture i regresja przeciwko fałszywemu alarmowi.
- https://www.gov.pl/web/paa/ocena-sytuacji-radiacyjnej-kraju — opis monitoringu.
- https://monitoring.paa.gov.pl/maps-portal/ — oficjalny portal pomiarów PAA.
- https://monitoring.paa.gov.pl/geoserver/ows — publiczny GeoServer/WFS używany przez portal; warstwa `paa:kcad_siec_pms_moc_dawki_mapa` zwraca punkty stacji i bieżącą moc dawki jako GeoJSON.

Kanał `PAA_MEASUREMENTS` jest uruchomiony przez adapter `paa-wfs/1.0.0`. Parser działa fail-closed: akceptuje wyłącznie oczekiwany FeatureCollection/Point, identyfikator i nazwę stacji, `tip_date`, `tip_value` oraz współrzędne w rozsądnym obrysie Polski. Nieznany format, pusty feed, duplikaty, błędna geometria lub przyszła data nie zastępują last-known-good. Dostęp WFS może podlegać ochronie WAF, dlatego po wdrożeniu produkcyjnym wymagany jest runtime check z Railway; awaria źródła ma dać BROKEN/STALE, a nie fałszywy brak zagrożenia.

## Backend

Komunikaty: SourceAdapter `paa-html/1.0.0`, polling minimum 5 min; health lastAttempt/lastSuccess, BROKEN, STALE po 15 min. Pomiary: `paa-wfs/1.0.0`, polling minimum 5 min, maksymalny wiek pomiaru 3 h. Nieudany format/HTTP nie zastępuje last-known-good. Publikacje normalizowane są jako RADIATION z URL, treścią i datą; data bez godziny pozostaje publicationDate, publishedAt=null. Pomiary są przechowywane osobno i nie są Eventami.

Indeks jest archiwum, **complete=false**. Trzy ostatnie strony nie dowodzą braku wcześniejszego aktywnego zagrożenia. Znane komunikaty są ponownie odczytywane także poza oknem archiwum (limit 100 URL, fail-closed). Wpisy redakcyjne nie są zdarzeniami. Rozpoznanie zagrożenia wymaga zamkniętej listy samodzielnych, jednoznacznych twierdzeń PAA o alarmie/ zagrożeniu na wskazanym terytorium. Nierozpoznana treść dostaje UNDETERMINED, a nie status bezpieczeństwa. Parser nie rozumie dowolnego języka naturalnego. Testowe komunikaty alarmowe i zakończone są jawnie syntetyczne — nie twierdzimy, że PAA opublikowała takie alarmy.

Pomiary nigdy nie trafiają do Event i nie generują progów alarmowych. Sieć pomiarowa jest wyłączona z obliczania hazard coverage — sama dostępność lub brak pomiarów nie daje statusu zielonego ani czerwonego. Explicit WARNING z kanału komunikatów może powodować CAUTION. Dla komunikatu bez validTo wymagana jest świeża synchronizacja źródła i obecność komunikatu w checkedEventIds ostatniego poprawnego odczytu; w przeciwnym razie pozostaje niepewność poprzedniego ostrzeżenia. Nie tworzy się CRITICAL na podstawie liczby µSv/h.

/v1/radiation, radiation w /status i /v1/snapshot; filtr source=PAA w GeoJSON zdarzeń. Mapa nie dostaje punktów komunikatów bez źródłowej geometrii. Trwałość SQL i cache Flutter zachowują dane po restartach i awariach.

## Flutter

Sekcja PAA na Statusie, filtr PAA w Alert Center i przełącznik Radiacja / PAA na mapie. Fioletowe punkty są dodatkową warstwą: nie wyłączają alertów, IMGW, obserwowanych miejsc ani schronień. Punkty są filtrowane do widocznego obszaru, a dotknięcie pokazuje nazwę stacji, wartość, jednostkę i czas pomiaru. Dane PAA są zapisywane w regionalnym snapshot cache wraz ze stanem źródeł. Offline komunikaty i pomiary tracą potwierdzenie aktualności; zachowuje się ostatnią poprawną kopię. Brak punktów nie jest potwierdzeniem bezpieczeństwa.

## Walidacja

Walidacja wymaga backend build/test, Flutter analyze/tests, Android build oraz osobnego live-checku komunikatów i WFS PAA. Live-check pomiarów zapisuje `AVAILABLE` lub kod błędu WAF/HTTP bez udawania danych. Po merge do main należy potwierdzić `/v1/radiation` i `PAA_MEASUREMENTS` na produkcyjnym Railway.

Bez CERT/CSIRT, SG, Ukrainy, NEPTUN, push i panelu administratora. Bez merge PR.
