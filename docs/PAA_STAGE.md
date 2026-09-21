# PAA — alpha.7 (ograniczona integracja)

Baza: stage/wczk-dedup, 4265b4873f3e7d64670cb7b931654026c9d2a646, PR #6 (bez merge).
Zweryfikowane zielone workflowy bazy: 35590901741 (PSP), 35590901780 (RCB), 35590897522 (preview).

## Oficjalne źródła i granice integracji

- https://www.gov.pl/web/paa/aktualnosci2 — dostępny oficjalny HTML, trzy strony publikacji; odnośniki paginacji pochodzą z HTML. Nie znaleziono zweryfikowanego API/feedu.
- https://www.gov.pl/web/paa/sytuacja-radiacyjna-w-normie--nie-ma-zagrozenia — rzeczywisty komunikat z 08.05.2026, fixture i regresja przeciwko fałszywemu alarmowi.
- https://www.gov.pl/web/paa/ocena-sytuacji-radiacyjnej-kraju — opis monitoringu.
- https://monitoring.paa.gov.pl/maps-portal/ — oficjalny portal pomiarów, wskazany przez PAA. W odpowiedzi pobranej 21.09.2026 pojawił się Web Application Firewall, event 110000003, signature. Nie obchodzono blokady. Próba odczytu interaktywnego nie wykonała się z powodu limitu automatycznej kontroli narzędzia.

**Działa kanał komunikatów. Kanał pomiarowy NIE jest uruchomiony.** Nie ma wymyślonego endpointu, wartości ani stacji. PAA_MEASUREMENTS pozostaje wyłączony z jawnym BLOCKED_SOURCE_VERIFICATION. Wewnętrzny model i atomowy magazyn pomiarów są przygotowaniem i mają wyłącznie syntetyczne testy; nie są kontraktem API PAA. Zakres współrzędnych w modelu odrzuca oczywiście błędne punkty, ale nie jest dokładną granicą Polski. Przed uruchomieniem stacji wymagane będą zweryfikowany format, źródłowe współrzędne i dokładna walidacja granic.

## Backend

SourceAdapter paa-html/1.0.0, polling minimum 5 min; health lastAttempt/lastSuccess, BROKEN, STALE po 15 min. Nieudany format/HTTP nie zastępuje last-known-good. Publikacje normalizowane jako RADIATION z URL, treścią i datą; data bez godziny pozostaje publicationDate, publishedAt=null. Nie dopisuje się geometrii ani domyślnej ważności.

Indeks jest archiwum, **complete=false**. Trzy ostatnie strony nie dowodzą braku wcześniejszego aktywnego zagrożenia. Znane komunikaty są ponownie odczytywane także poza oknem archiwum (limit 100 URL, fail-closed). Wpisy redakcyjne nie są zdarzeniami. Rozpoznanie zagrożenia wymaga zamkniętej listy samodzielnych, jednoznacznych twierdzeń PAA o alarmie/ zagrożeniu na wskazanym terytorium. Nierozpoznana treść dostaje UNDETERMINED, a nie status bezpieczeństwa. Parser nie rozumie dowolnego języka naturalnego. Testowe komunikaty alarmowe i zakończone są jawnie syntetyczne — nie twierdzimy, że PAA opublikowała takie alarmy.

Pomiary nigdy nie trafiają do Event i nie generują progów alarmowych. Explicit WARNING może powodować CAUTION. Dla komunikatu bez validTo wymagana jest świeża synchronizacja źródła i obecność komunikatu w checkedEventIds ostatniego poprawnego odczytu; w przeciwnym razie pozostaje niepewność poprzedniego ostrzeżenia. Nie tworzy się CRITICAL na podstawie liczby nSv/h. STALE/BROKEN pogarsza coverageState.

/v1/radiation, radiation w /status i /v1/snapshot; filtr source=PAA w GeoJSON zdarzeń. Mapa nie dostaje punktów komunikatów bez źródłowej geometrii. Trwałość SQL i cache Flutter zachowują dane po restartach i awariach.

## Flutter

Sekcja PAA na Statusie, filtr PAA w Alert Center, przełącznik Radiacja / PAA w istniejącej mapie. Niedostępny kanał pomiarowy ma jasny komunikat. Dane PAA są zapisywane w regionalnym snapshot cache wraz ze stanem źródeł. Offline komunikaty i pomiary tracą potwierdzenie aktualności; zachowuje się treść ostatniej poprawnej kopii. Przygotowane punkty pomiarowe są filtrowane do widocznego obszaru; obecna integracja nie dostarcza punktów. Brak mapy/punktów nie jest potwierdzeniem bezpieczeństwa.

## Walidacja

Wyniki bieżącej walidacji i APK zostaną uzupełnione po CI. Workflow alpha.7 wymaga backend build, wszystkich testów z prawdziwym PostGIS, Flutter analyze/tests, Android build oraz odczytu komunikatów PAA. Podpis debug/preview, nie produkcyjny. Backend nie jest wdrażany.

Bez CERT/CSIRT, SG, Ukrainy, NEPTUN, push i panelu administratora. Bez merge PR.
