# Plan prac — Bezpieczna Polska

Przegląd: **4 października 2026**. Stan odnosi się do wspólnego kodu po [integracji 17 PR-ów](PR_INTEGRATION_2026-10-04.md). Aktualny runtime należy sprawdzać osobno. Datowane
audyty i wcześniejsze etapy nie są listą ukończonych zadań produkcyjnych.

## P0 — przed szerszą publikacją Androida

| Zadanie | Obecny stan | Kryterium zakończenia |
| --- | --- | --- |
| Rzetelny ekran Start | Lokalny zakres, limit trzech komunikatów i świeżość są w kodzie | Build i test na telefonie; tytuł, zakres, komunikaty i świeżość opisują ten sam zbiór danych |
| Cykl życia ostrzeżeń push | TTL, odrzucanie nieaktualnej kolejki, kanały ważności i otwieranie alertu są w kodzie | Aktualne zdarzenie → kolejka → telefon w tle → kliknięcie → właściwy alert; stare zdarzenie nie jest wysyłane |
| Prywatność | Ekran, [projekt polityki](PRIVACY_POLICY_DRAFT.md), Data safety i plan testów są w repozytorium | Uzupełniony administrator/kontakt, opis dostawców i retencji, publiczna polityka HTML w aplikacji i Play, zgodna deklaracja Data safety |
| Dostępność i odporność na błędy | [Scenariusze testów Androida](ANDROID_USER_ACCEPTANCE.md) są w repozytorium | Rzeczywiste próby dużego tekstu/TalkBack, odmowy GPS i powiadomień, słabej sieci oraz długotrwałej mapy |
| Dystrybucja produkcyjna | Pipeline AAB/APK i kontrola podpisu istnieją | Zweryfikowane artefakty, backend, podpisy, rejestracja Firebase i test na urządzeniu |
| Testy Google Play | Stan udziału testerów nie został zweryfikowany w repozytorium | Wymagany closed test dla właściwego typu konta, zebrany feedback i pozytywny wniosek o dostęp do produkcji |

Zgoda systemowa na GPS/powiadomienia nie zastępuje opisu przetwarzania danych.
Backend zapisuje współrzędne obserwowanych miejsc przy włączonej kategorii
push. Wyrejestrowanie usuwa aktywny token i preferencje z rekordu urządzenia,
ale nie całą historię kolejki ani wszystkie kopie zapasowe.

## P1 — niezawodność i większy ruch

| Zadanie | Obecny stan | Następny dowód |
| --- | --- | --- |
| Migracja danych między wydaniami APK | Test CI preview oraz [kontrola oryginalnych APK i procedura](ANDROID_RELEASE_MIGRATION.md) | Poprzedni publiczny APK → dokładny kandydat na ARM64; zachowane ustawienia, lokalizacje, secure storage i działający push |
| Zgodność GitHub ↔ Play | Różne pakiety development/preview/production; certyfikaty sklepu wymagają osobnej kontroli | Ten sam production applicationId, kompatybilny app signing certificate/lineage i rosnący versionCode; upload key nie jest wystarczającym dowodem |
| Schronienia i wydajność backendu | Aktualizacja różnic w PostGIS/SQLite i [metryki](BACKEND_CAPACITY.md) są w kodzie | Realny PostGIS, pomiary dużego katalogu, aktualizacja różnic, brak blokowania zwykłych odczytów |
| Monitoring | Health/ready, audit i metryki kolejki, workerów, backupu oraz dysku są w kodzie | Alarmy dla wieku push, opóźnienia workerów, backupu i dysku; mierzalne progi i odpowiedzialność za reakcję |
| Pokrycie źródeł | Adaptery i deduplikacja istnieją; nie są dowodem pełnego pokrycia | Aktualny przegląd RSO/WCZK i stanu każdego istotnego źródła; jasna informacja o brakach |
| Offline | Dane i pakiety regionów, bez pełnego basemapu | Lekki podkład lub czytelny widok tekstowy schronienia; odległość w linii prostej odróżniona od trasy; tryb samolotowy po restarcie |
| Odzyskiwanie infrastruktury | Skrypty backupu/restore i kopii konfiguracji istnieją | Monitoring i retencja wszystkich kopii oraz pełne ćwiczenie odtworzenia nowej VM |

Opcjonalne role API/worker z domyślnym trybem combined jest opcją wdrożenia na tym samym
hoście. Rozbudowa infrastruktury powinna wynikać z pomiarów; nie ma potrzeby
przepisywania całej architektury tylko z powodu wzrostu liczby użytkowników.

## Funkcje i źródła obecne w kodzie

Na `main` istnieją Start/Alerty/Mapa, wyszukiwanie schronień i nawigacja,
obserwowane miejsca, pakiety offline, stopnie alarmowe, PAA, NEPTUN,
GPSJAM i UkraineAlarm. Android używa FCM; iOS/APNs pozostaje poza bieżącym
priorytetem wydania. Lista możliwości znajduje się w [README](../README.md).

Źródła monitoruje `/v1/sources`. Przydatność integracji wymaga osobnej oceny
technicznej świeżości, zakresu pokrycia i znaczenia pustego wyniku. Nie stosujemy
stałych zielonych statusów w roadmapie dla danych, które zmieniają się w runtime.
Dawny audyt WCZK-18 i schronień zapisano w
[historii infrastruktury](INFRASTRUCTURE_STATUS_2026-10-04.md).

## Wdrożenie i porządek repozytorium

- Adresy `PRODUCTION_API_BASE_URL` i `PREVIEW_API_BASE_URL` są decyzją operacyjną;
  porządkowanie dokumentacji ich nie zmienia.
- Railway dla starszych klientów wymaga kontrolowanego wygaszenia. Brak
  automatycznej replikacji wyklucza traktowanie go jako aktualnego failoveru.
- Kontrakt wdrożenia i audit używają ogólnego BUILD_SHA; adapter zgodności
  zachowuje starsze środowisko Railway. Buildy wymagają jawnych zmiennych API.
- Porównanie równoległych backendów jest manualnym workflowem.
- Fixture schronień używają dat względnych; ikony NEPTUN mają czytelne oznaczenia typu.
- Scalenie kodu nie potwierdza wdrożenia backendu ani prób na fizycznym urządzeniu.

Reguły gałęzi: [REPOSITORY_MAINTENANCE.md](REPOSITORY_MAINTENANCE.md).

## Później

Własna trwała domena API, dalszy rozwój offline i ewentualne narzędzia
administracyjne po zamknięciu powyższych prac. iOS, Xcode i App Store są odłożone.

Zasada produktu: brak danych nie oznacza bezpieczeństwa, a wynik technicznego
smoke testu nie zastępuje testu sytuacji użytkownika ani kompletności źródeł.
