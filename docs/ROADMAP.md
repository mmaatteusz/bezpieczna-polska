# ROADMAP — Bezpieczna Polska

Aktualizacja: 26.09.2026.

Legenda: ✅ gotowe i używane • 🟡 kod istnieje / wymaga wdrożenia lub domknięcia • ⛔ świadomie wyłączone • ❌ do zrobienia.

## P0 — przed publicznym Androidem

| Element | Stan | Następny krok |
|---|:---:|---|
| Backend Railway śledzi `main` | ✅ | utrzymać runtime audit |
| Runtime audit po deployu | ✅ | utrzymać krytyczne źródła i test NEPTUN |
| Android preview signing | ✅ | nie zmieniać signera |
| Aktualizacja APK „na siebie” | ✅ | test CI ma pozostać blokujący |
| Monotoniczny `versionCode` | ✅ | utrzymać wspólną linię preview/release |
| Production release pipeline | ✅ | wymaga finalnego signera i sekretów |
| Finalny production keystore | 🟡 | jednorazowo wygenerować i zrobić offline backup |
| Pierwszy podpisany production AAB/APK | ❌ | uruchomić po konfiguracji keystore |
| FCM Android | 🟡 | skonfigurować provider i sekrety backendu |
| Polityka prywatności | ❌ | przygotować przed testem sklepowym |
| Google Play Data Safety | ❌ | uzupełnić na podstawie faktycznej konfiguracji |
| Google Play Internal Test | ❌ | pierwszy kanał dystrybucji produkcyjnej |
| Branch protection `main` | ❌ | wymagać kluczowych checków CI |

## Funkcje aplikacji

| Element | Stan | Uwagi |
|---|:---:|---|
| Start: Polska / okolica / istotne zagrożenia | ✅ | główny UX |
| Alert Center + filtry + wyszukiwanie | ✅ | deduplikacja i historia |
| Mapa Polski + województwa | ✅ | zdarzenia i schronienia zależnie od zoom |
| Schronienia + nearest | ✅ | PostGIS + offline |
| Obserwowane miejsca | ✅ | lokalnie, bez śledzenia w tle |
| `Wokół mnie` | ✅ | GPS tylko po akcji użytkownika |
| Offline LAST KNOWN GOOD | ✅ | bez pełnego basemapu |
| NEPTUN | ✅ | live, zgrubna pozycja |
| Stopnie alarmowe RP — backend | ✅ | źródło live |
| Stopnie alarmowe RP — dedykowany panel | 🟡 | widget istnieje, trzeba wystawić go w bieżącym UI |
| PAA komunikaty | ✅ | oficjalne komunikaty |
| PAA dedykowany panel | 🟡 | widget istnieje, trzeba zdecydować miejsce w UI |
| PAA pomiary stacji | ⛔ | brak zweryfikowanego kontraktu |
| UkraineAlarm backend/UI | 🟡 | kod istnieje; brak klucza i produkcyjnego włączenia |
| Push UI/outbox/backend | 🟡 | kod gotowy, produkcyjny provider nie skonfigurowany |
| `Jestem bezpieczny` | ✅ | systemowy Share Sheet |
| Pełny basemap offline | ❌ | etap późniejszy |

## Źródła

| Źródło | Stan |
|---|:---:|
| RCB | ✅ |
| RSO | ✅ |
| WCZK przez RSO | ✅ |
| WCZK-18 direct mirror | ✅ |
| IMGW meteo | ✅ |
| IMGW hydro | ✅ |
| PAA komunikaty | ✅ |
| CERT Polska | ✅ |
| Straż Graniczna | ✅ |
| Policja | ✅ |
| PSP incidents | ✅ |
| Schronienia PSP/dane.gov.pl | ✅ |
| Stopnie alarmowe RP | ✅ |
| NEPTUN | ✅ |
| PAA measurements | ⛔ |
| CSIRT GOV | ⛔ |
| UkraineAlarm live | 🟡 |

WCZK nie jest modelowane jako 16 niezależnych feedów. RSO jest krajowym kanałem publikacji komunikatów WCZK, a Podkarpackie ma dodatkowy oficjalny mirror tego samego wydawcy.

## Infrastruktura do posprzątania

Na Railway po potwierdzeniu backupu można usunąć historyczne zasoby:

- `PostGIS 17-x_Uh`,
- `api-alpha20-smoke`,
- `alpha20-runtime-probe`.

W repo należy utrzymywać tylko aktywne branche robocze. Historyczne branche po scalonych hotfixach powinny być kasowane; historia pozostaje w commitach i PR.

## P1

1. Podpiąć stopnie alarmowe do aktualnego UI.
2. Uporządkować prezentację PAA.
3. Włączyć FCM i wykonać test end-to-end powiadomienia na fizycznym Androidzie.
4. Po otrzymaniu klucza skonfigurować UkraineAlarm, zweryfikować live i dopiero wtedy wystawić moduł w aplikacji.
5. Posprzątać Railway po backupie.
6. Uporządkować monitoring, backup i restore drill.

## P2

1. Panel administratora z rolami i MFA.
2. Pełny kontrolowany basemap offline.
3. Własna domena API.
4. iOS production signing, urządzenie fizyczne i App Store.
5. Dalsza optymalizacja wydajności `/v1/snapshot` i `/v1/around`.

## Niezmienne zasady

Brak danych nie oznacza bezpieczeństwa. Źródła częściowe nie są przedstawiane jako kompletne. Nie publikujemy fikcyjnej geometrii. STALE musi być widoczne. Stopnie alarmowe są informacją o gotowości administracyjnej, nie automatycznym alarmem dla mieszkańca. NEPTUN pozostaje osobnym źródłem informacyjnym i nie zastępuje oficjalnych alarmów.
