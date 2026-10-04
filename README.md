# Bezpieczna Polska

<p align="center">
  <img src="mobile/assets/brand/bezpieczna_polska_logo_transparent.png" width="260" alt="Logo Bezpieczna Polska">
</p>

**Ostrzeżenia, mapa i schronienia dla Polski w jednej aplikacji Android.**

Bezpieczna Polska zbiera komunikaty z oficjalnych źródeł, pokazuje ich zasięg i świeżość oraz ułatwia znalezienie miejsc schronienia. Łączy informacje dla wybranego regionu z mapą, obserwowanymi miejscami, powiadomieniami i danymi dostępnymi offline.

[Wydania Android](https://github.com/mmaatteusz/bezpieczna-polska/releases) · [Dokumentacja](docs/README.md) · [Plan prac](docs/ROADMAP.md) · [Otwarte PR-y](https://github.com/mmaatteusz/bezpieczna-polska/pulls) · [Zgłoś problem](https://github.com/mmaatteusz/bezpieczna-polska/issues/new/choose)

[![Regresja i kontrola wydania](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/production-release.yml/badge.svg?branch=main)](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/production-release.yml)
[![Aktualizacja APK](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/android-update-compat.yml/badge.svg?branch=main)](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/android-update-compat.yml)

> Aplikacja jest niezależnym projektem w fazie alpha. Nie jest państwowym systemem alarmowym i nie zastępuje Alertu RCB, numeru 112 ani komunikatów służb. Brak komunikatów nie oznacza braku zagrożenia.

## Stan projektu i pobieranie

Aktualny kod rozwojowy: **0.1.0-alpha.69** (`build 70`).

**Android jest priorytetem.** Publikacja w Google Play pozostaje w przygotowaniu. Kod i konfiguracja iOS znajdują się w repozytorium, lecz iOS nie jest obecnie celem wydania.

APK pobieraj z [GitHub Releases](https://github.com/mmaatteusz/bezpieczna-polska/releases) lub z artefaktów konkretnego zakończonego builda w [GitHub Actions](https://github.com/mmaatteusz/bezpieczna-polska/actions). Sprawdź release notes: pakiet, podpis, numer buildu, konfiguracja backendu i dostępne funkcje zależą od wydania. Wersja `main`, działającego API i opublikowanego APK mogą się różnić.

| Artefakt | Zastosowanie |
| --- | --- |
| Preview APK ARM64 | Testy na telefonie Android z procesorem ARM64; pakiet preview |
| Produkcyjny APK ARM64 | Instalacja podpisanego wydania produkcyjnego |
| Produkcyjny AAB | Przesłanie do Google Play; nie jest plikiem do zwykłej instalacji na telefonie |
| `SHA256SUMS.txt` | Sprawdzenie integralności artefaktów konkretnego wydania |

Automatyczne podbicie alphy nie oznacza publikacji w sklepie ani wdrożenia backendu. Więcej: [kanały Android, podpisy i wydania](docs/PRODUCTION_RUNBOOK.md).

## Funkcje obecne na `main`

| Obszar | Możliwości i granice |
| --- | --- |
| Start i alerty | Status Polski/wybranego województwa, stopnie alarmowe, filtrowanie i grupowanie komunikatów, szczegóły oraz historia. Lokalna sytuacja ma jawny zakres, najwyżej trzy komunikaty i ocenę świeżości źródeł. |
| Mapa | Warstwy komunikatów, IMGW, schronień i PAA; granice województw, szczegóły obiektów i legenda zależna od widoku. |
| Schronienia | Lista, wyszukiwanie, najbliższe punkty i przejście do zewnętrznej nawigacji. Wpis w katalogu nie gwarantuje otwarcia ani dostępności obiektu. |
| PAA | Komunikaty i pomiary promieniowania z datą oraz źródłem. |
| NEPTUN | Odświeżane dane sytuacyjne i szczegóły punktów. Położenie jest celowo przybliżone; ikona nie określa kierunku lotu. |
| Ukraina | Warstwa UkraineAlarm API v3, gdy backend ma klucz. Alarmy Ukrainy nie zmieniają statusu Polski. |
| GNSS / GPS | Dzienne dane GPSJAM o dokładności pozycji samolotów oraz odnośnik do zewnętrznej mapy RTGMS. GPSJAM nie jest pomiarem GPS telefonu ani samodzielnym dowodem zagłuszania. |
| Obserwowane miejsca i push | Zapis miejsc, wybór kategorii, rejestracja urządzenia i rzeczywisty test push przez backend. |
| Offline | Pakiety regionów i ostatnia poprawna kopia danych. **Pełny podkład mapowy nie jest zawarty w pakietach.** |

Dostępność danych zależy od konfiguracji wydania, połączenia, źródeł i ich stanu. Lista funkcji nie jest potwierdzeniem kompletności pokrycia ani testu wszystkich scenariuszy na telefonach.

## Źródła i świeżość

Backend integruje m.in. **RCB, RSO/WCZK, stopnie alarmowe RP, IMGW METEO/HYDRO, PAA, schronienia PSP/dane.gov.pl, CERT Polska, Straż Graniczną, Policję, PSP, UkraineAlarm i NEPTUN**.

Bieżący stan integracji: [`/v1/sources`](https://bezpieczna-polska-api.duckdns.org/v1/sources). Wersja uruchomionego backendu: [`/health`](https://bezpieczna-polska-api.duckdns.org/health). Opis źródeł i ograniczeń: [SOURCES.md](docs/SOURCES.md).

- `HEALTHY` opisuje techniczną poprawność i świeżość integracji; nie gwarantuje wiedzy o wszystkich zagrożeniach.
- Przy błędzie może zostać zachowana ostatnia poprawna kopia z oznaczeniem degradacji lub nieaktualności.
- Źródła mają różne role: `STATUS`, `CONTEXT`, `REFERENCE`, `SITUATIONAL`. Pustego wyniku częściowego nie wolno traktować jak potwierdzenia braku zagrożeń.
- WCZK publikuje także przez RSO. Komunikaty tego samego wydawcy wymagają deduplikacji, a pokrycie nie oznacza 16 niezależnych pełnych feedów.

Wyniki wcześniejszych audytów są zapisami z konkretnego dnia. [Stan infrastruktury i audyty](docs/INFRASTRUCTURE_STATUS_2026-10-04.md) nie zastępują kontroli aktualnego runtime.

## Co pozostaje przed publikacją

| Priorytet | Zadanie | Stan pracy |
| --- | --- | --- |
| P0 | Precyzyjna sytuacja lokalna na Start, świeżość wszystkich istotnych źródeł | Kod zintegrowany; pozostaje próba na rzeczywistym Androidzie |
| P0 | Wygaśnięcie push, odrzucanie starych komunikatów i otwieranie właściwego alertu | Kod zintegrowany: TTL, ponowna kontrola aktualności i otwieranie alertu; pozostaje test urządzenia |
| P0 | Pełna polityka prywatności, publiczny kontakt, retencja i Data safety | Ekran jest w aplikacji; [projekt polityki](docs/PRIVACY_POLICY_DRAFT.md) i [Data safety](docs/PLAY_DATA_SAFETY.md) wymagają uzupełnienia |
| P0 | TalkBack, duży tekst, odmowa GPS/push, słaba sieć i dłuższe działanie mapy | Próby z rzeczywistymi użytkownikami pozostają do wykonania |
| P1 | Poprzedni publiczny APK → nowy APK z zachowaniem danych i push | [Kontrola artefaktów i procedura](docs/ANDROID_RELEASE_MIGRATION.md) są w repozytorium; pełny test migracji pozostaje do wykonania |
| P1 | Wydajność backendu i monitoring przed większym ruchem | Aktualizacja różnic, metryki i opcjonalne role procesów są w kodzie; [pomiary i wdrożenie](docs/BACKEND_CAPACITY.md) wymagają weryfikacji na hoście |

Pozostałe zadania i kolejność wdrożeń: [ROADMAP.md](docs/ROADMAP.md). [Integracja 17 PR-ów](docs/PR_INTEGRATION_2026-10-04.md) łączy poprawki we wspólnym kodzie. Opublikowany APK i działający backend wymagają osobnego builda oraz wdrożenia.

## Prywatność i powiadomienia

Aplikacja zapisuje ustawienia i miejsca na telefonie. Zapytania o okolicę i najbliższe schronienia wysyłają współrzędne do API. Po włączeniu push dla obserwowanych miejsc backend przechowuje ich nazwy, współrzędne i promienie wraz z preferencjami oraz identyfikatorem instalacji. Android używa **Firebase Cloud Messaging**. Podkład mapowy pobierany jest od zewnętrznego dostawcy.

Wyrejestrowanie push usuwa aktywny token i lokalizacje z rekordu urządzenia, lecz nie usuwa całej historii technicznej ani wszystkich kopii zapasowych. Ekran „Polityka prywatności” w aplikacji opisuje te przepływy. Pełna polityka i Data safety nadal wymagają danych administratora, kontaktu i rzeczywistej retencji. Produkcyjne wydanie wymaga publicznego adresu HTTPS polityki HTML (`PRIVACY_POLICY_URL`).

Test wysłany przez backend nie dowodzi wyświetlenia na telefonie. Odbiór należy potwierdzić na urządzeniu, również w tle, po ponownym uruchomieniu i przy ograniczeniach baterii.

## Aktualizacje Androida

| Kanał | Application ID |
| --- | --- |
| Development | `pl.bezpiecznapolska.dev` |
| Preview | `pl.bezpiecznapolska.preview` |
| Production | `pl.bezpiecznapolska` |

Preview i production są **osobnymi aplikacjami**. Aktualizacja bez odinstalowania wymaga zgodnego pakietu, kompatybilnego podpisu i odpowiednio wyższego `versionCode`. Test CI na dwóch wariantach preview potwierdza instalację „na siebie” i zachowanie pliku kontrolnego; nie potwierdza pełnej migracji ustawień ze starego publicznego wydania.

Przy przechodzeniu GitHub ↔ Google Play trzeba porównać certyfikat **app signing** ze sklepu z podpisem APK. Klucz **upload** AAB może być inny. Użycie tego samego upload key nie jest dowodem zgodności instalacji między kanałami.

## Backend i wdrożenia

Backend: **Node.js 24 + TypeScript + Fastify + PostgreSQL/PostGIS**. Klient: **Flutter + MapLibre + Firebase Messaging**.

Adres Oracle opisany w runbooku: **https://bezpieczna-polska-api.duckdns.org**. Konfiguracja: Ubuntu ARM64, Docker, nginx/HTTPS i PostGIS. Skrypty obejmują audyt hosta, wdrożenie określonego SHA, backup poza VM i odzyskiwanie konfiguracji.

Railway obsługuje okres przejściowy i starsze APK. Samo pozostawienie tej usługi nie daje automatycznej replikacji bazy ani aktualnego failoveru. Adres zapisany w istniejącym APK nie zmienia się po zmianie zmiennej CI.

- [Uruchomienie i wydanie produkcyjne](docs/PRODUCTION_RUNBOOK.md)
- [Przejście na Oracle](docs/ORACLE_CUTOVER_RUNBOOK.md)
- [Backup poza VM i odzyskiwanie](docs/ORACLE_OFF_VM_BACKUP.md)
- [Skrypty infrastruktury](infra/oracle/README.md)

## Uruchomienie lokalne

Wymagania: **Node.js 24**, **Flutter 3.47.4** (wersja z CI), narzędzia Android SDK dla buildów i PostgreSQL/PostGIS dla testów integracyjnych.

```bash
# Backend deweloperski — domyślnie lokalna baza SQLite
cd backend
npm ci
npm run build
npm test
npm start
```

Testy PostGIS wymagają osobnej testowej bazy i `TEST_DATABASE_URL`; bez niej część testów integracyjnych jest pomijana. W produkcji PostgreSQL jest wymagany. Sekrety i dane środowiska opisuje [runbook](docs/PRODUCTION_RUNBOOK.md).

```bash
# Z głównego katalogu repozytorium
cd mobile
flutter pub get
flutter analyze
flutter test

# Uruchomienie development przeciwko publicznemu API
flutter run --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=https://bezpieczna-polska-api.duckdns.org
```

Lokalny build development ma osobną tożsamość. Buildy preview i production wymagają odpowiednich kluczy podpisujących; używaj opisanych workflowów, aby zachować zgodność aktualizacji.

## CI i praca nad projektem

CI obejmuje testy backendu i Flutter, prawdziwy PostGIS, migracje i backup/restore, kontrakty źródeł, podpisy Androida oraz próbę aktualizacji APK. Kontrole dostępności zewnętrznych źródeł mogą mieć charakter diagnostyczny; nie każdy workflow jest bramką wydania.

[Spis aktywnych workflowów](docs/WORKFLOW_AUDIT.md) · [Zasady wkładu i zgłoszeń](CONTRIBUTING.md) · [Porządek PR-ów i gałęzi](docs/REPOSITORY_MAINTENANCE.md)

Automatyczne sprzątanie gałęzi zachowuje `main`, chronione gałęzie i gałęzie otwartych PR-ów. Usuwa zakończone gałęzie tylko po sprawdzeniu historii lub dokładnego SHA zakończonej pracy.

## Struktura repozytorium

| Katalog | Zawartość |
| --- | --- |
| `mobile/` | Aplikacja Flutter, interfejs i konfiguracja Android/iOS |
| `backend/` | API, adaptery źródeł, baza, synchronizacja i push |
| `infra/oracle/` | Wdrożenie, audyt hosta, backup i odzyskiwanie |
| `scripts/` | Wersjonowanie, signing, kontrola artefaktów i utrzymanie repozytorium |
| `.github/workflows/` | CI, buildy, audyty i automatyzacja |
| `docs/` | Dokumentacja operacyjna, źródła i historyczne audyty |

Pełny indeks: **[docs/README.md](docs/README.md)**. Dokumenty dawnych etapów `ALPHA*`, `*_STAGE` i audyty z datą zachowujemy jako historię decyzji; nie są potwierdzeniem aktualnego wdrożenia.
