# Bezpieczna Polska

<p align="center">
  <img src="mobile/assets/brand/bezpieczna_polska_logo_transparent.png" width="260" alt="Logo Bezpieczna Polska">
</p>

**Ostrzeżenia, mapa i schronienia dla Polski w jednej aplikacji Android.**

Bezpieczna Polska zbiera komunikaty z oficjalnych źródeł, pokazuje ich zasięg i świeżość oraz ułatwia znalezienie miejsc schronienia. Łączy informacje dla wybranego regionu z mapą, obserwowanymi miejscami, powiadomieniami i danymi dostępnymi offline.

[Wydania Android](https://github.com/mmaatteusz/bezpieczna-polska/releases) · [Dokumentacja](docs/README.md) · [Plan prac](docs/ROADMAP.md) · [Otwarte PR-y](https://github.com/mmaatteusz/bezpieczna-polska/pulls) · [Zgłoś problem](https://github.com/mmaatteusz/bezpieczna-polska/issues/new/choose)

[![Regresja i kontrola wydania](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/production-release.yml/badge.svg?branch=main)](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/production-release.yml)
[![Aktualizacja APK](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/android-update-compat.yml/badge.svg?branch=main)](https://github.com/mmaatteusz/bezpieczna-polska/actions/workflows/android-update-compat.yml)

> Aplikacja jest niezależnym projektem w fazie beta. Nie jest państwowym systemem alarmowym i nie zastępuje Alertu RCB, numeru 112 ani komunikatów służb. Brak komunikatów nie oznacza braku zagrożenia.

## Stan projektu i pobieranie

Aktualny kod rozwojowy: **0.1.0-beta.3** (`build 80`).

**Android jest priorytetem.** Publikacja w Google Play pozostaje w przygotowaniu. Kod i konfiguracja iOS znajdują się w repozytorium, lecz iOS nie jest obecnie celem wydania.

APK pobieraj z [GitHub Releases](https://github.com/mmaatteusz/bezpieczna-polska/releases) lub z artefaktów konkretnego zakończonego builda w [GitHub Actions](https://github.com/mmaatteusz/bezpieczna-polska/actions). Sprawdź release notes: pakiet, podpis, numer buildu, konfiguracja backendu i dostępne funkcje zależą od wydania. Wersja `main`, działającego API i opublikowanego APK mogą się różnić.

| Artefakt | Zastosowanie |
| --- | --- |
| Preview APK ARM64 | Testy na telefonie Android z procesorem ARM64; pakiet preview |
| Produkcyjny APK ARM64 | Instalacja podpisanego wydania produkcyjnego |
| Produkcyjny AAB | Przesłanie do Google Play; nie jest plikiem do zwykłej instalacji na telefonie |
| `SHA256SUMS.txt` | Sprawdzenie integralności artefaktów konkretnego wydania |

Workflow `Auto bump prerelease on main` synchronizuje wersję backendu, klienta i dokumentacji oraz uruchamia build testowego APK. Samo podbicie wersji nie oznacza publikacji w sklepie ani wdrożenia backendu. Więcej: [kanały Android, podpisy i wydania](docs/PRODUCTION_RUNBOOK.md).

Wydanie przygotowywane do publikacji: **0.1.0-beta.3** — poprawka widoczności schronień na mapie, APK preview oraz podpisany AAB do testów Google Play, jeśli kontrola konfiguracji produkcyjnej i build zakończą się pomyślnie. Zmiany i ograniczenia: [release notes](docs/releases/0.1.0-beta.3.md). Dostępne wydanie: [beta.2](https://github.com/mmaatteusz/bezpieczna-polska/releases/tag/v0.1.0-beta.2); backend Oracle beta.2 zawiera już poprawki powiadomień. Wcześniejsze beta.1 nie zostało opublikowane.

Workflow [Publish Android beta](.github/workflows/beta-release.yml) dla commita oznaczonego `[release-beta]` czeka na pełną regresję i kontrolę infrastruktury, wdraża jego dokładny SHA na Oracle, a następnie publikuje prerelease z przetestowanym APK ARM64 i sumą SHA-256. APK zawiera konfigurację Firebase. Backend przed wysyłką ponownie sprawdza preferencje urządzenia; zakończenie alarmu UkraineAlarm wywnioskowane tylko ze zniknięcia z feedu nie powoduje push (pozostaje w historii).

Marker `[release-beta-test]` publikuje **wydanie testowe Androida** po tych samych testach kodu i kontroli działającego API, bez wdrażania backendu. Opis automatycznie zawiera faktyczną wersję i commit Oracle. Nowe poprawki serwerowe wymagają osobnego wdrożenia; zmiany wyłącznie w aplikacji mogą korzystać ze sprawdzonego działającego API. Nie łączymy tych dwóch markerów w jednym commicie. Publikacja nigdy nie nadpisuje istniejącego wydania.

Marker `[release-play-bundle]` razem z markerem beta zleca także budowę AAB `pl.bezpiecznapolska` do testów Play Console. Wymaga istniejącego podpisu produkcyjnego, osobnej aplikacji Firebase i publicznej polityki prywatności. AAB przechodzi weryfikację podpisu, struktury, pakietu i versionCode; nie zastępuje APK preview. Zwykła bramka wydania produkcyjnego nadal wymaga zgodnej wersji i SHA backendu. Jawne wydanie beta zachowuje przygotowany numer i nie uruchamia dodatkowego automatycznego podbicia.


Po ręcznym wdrożeniu na VM można wznowić publikację przez `workflow_dispatch` w `Publish Android beta`: dokładny `target_sha`, ID udanej regresji z pusha na `main` oraz tryb `verified-backend`. Workflow wymaga zgodnej wersji i SHA działającego backendu, gotowego PostgreSQL/PostGIS oraz pełnego audytu API. Nie potrzebuje wtedy ponownego połączenia SSH. Procedura: [Oracle](infra/oracle/README.md).

## Funkcje obecne na `main`

| Obszar | Możliwości i granice |
| --- | --- |
| Start i alerty | Lokalna sytuacja, najwyżej trzy najważniejsze komunikaty i szybkie przejście do mapy lub alertów. Status kraju, stopnie alarmowe i zakres danych są rozwijane. Krytyczne zagrożenie krajowe pozostaje widoczne bez rozwijania. |
| Mapa | Warstwy komunikatów, IMGW, schronień i PAA; granice województw, szczegóły obiektów i legenda zależna od widoku. |
| Schronienia | Lista, wyszukiwanie, najbliższe punkty i przejście do zewnętrznej nawigacji. Wpis w katalogu nie gwarantuje otwarcia ani dostępności obiektu. |
| PAA | Komunikaty i pomiary promieniowania z datą oraz źródłem. |
| NEPTUN | Dane live odświeżane co około 5 sekund, szczegóły wpisów i historyczne ślady. Ikony typów pozostają widoczne po oddaleniu mapy; dotknięcie nakładających się punktów pozwala wybrać wpis. Położenie jest celowo przybliżone; ikona nie określa kierunku lotu. |
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

## Architektura: Oracle, Firebase i Android

Backend: **Node.js 24 + TypeScript + Fastify + PostgreSQL/PostGIS**. Klient: **Flutter + MapLibre + Firebase Messaging**.

| Element | Rola w projekcie |
| --- | --- |
| Android | Wyświetla alerty i mapy, zapisuje ustawienia oraz dane offline, rejestruje urządzenie do push i otwiera wskazany komunikat |
| Oracle Cloud Infrastructure (OCI) | Utrzymuje API, PostgreSQL/PostGIS, pobieranie źródeł, kolejkę powiadomień oraz kopie zapasowe |
| Firebase Cloud Messaging (FCM) | Dostarcza na Androida wiadomości wysłane przez backend; projekt nie korzysta z Firebase jako głównej bazy ani hostingu API |
| nginx + HTTPS | Przyjmuje publiczne połączenia i przekazuje je do API na localhost |
| OCI Object Storage | Miejsce na kopie poza VM i zaszyfrowane materiały odzyskiwania według runbooka |
| Railway | Starsze środowisko dla okresu przejściowego; brak automatycznej replikacji z Oracle |
| GitHub Actions | Testuje kod, buduje i podpisuje APK/AAB oraz wykonuje jawnie wybrane wdrożenia i audyty |

Telefon pobiera dane z Oracle przez HTTPS. Po włączeniu powiadomień uzyskuje token FCM i rejestruje go wraz z preferencjami w API. Backend dobiera ostrzeżenia i wysyła je do FCM, który przekazuje powiadomienie do telefonu. Przeniesienie API z Railway na Oracle nie zastępuje Firebase ani nie zmienia projektu FCM.

## Oracle Cloud — backend i utrzymanie

Adres API używany przez obecne buildy z konfiguracją Oracle:

**https://bezpieczna-polska-api.duckdns.org**

Ostatni zapis konfiguracji hosta: **OCI Frankfurt, Ubuntu 24.04 ARM64, `VM.Standard.A1.Flex`, 1 OCPU, 6 GB RAM i boot volume około 100 GB**. Baza: PostgreSQL 17 + PostGIS 3.6. To opis wdrożonej konfiguracji z [zapisu infrastruktury](docs/INFRASTRUCTURE_STATUS_2026-10-04.md), a nie gwarancja dostępności lub limitów oferty Always Free.

- API działa w Dockerze, uruchamiane przez `bezpieczna-polska-api.service`; nginx wystawia HTTPS z certyfikatem odnawianym przez Certbot.
- API (`127.0.0.1:8080`) i PostgreSQL (`127.0.0.1:5432`) pozostają prywatne. Publiczne są porty 80/443; dostęp SSH należy ograniczyć administracyjnie.
- Konfiguracja i sekrety są w `/etc/bezpieczna-polska/backend.env` z prawami `600`. Wzór: [backend.env.example](infra/oracle/backend.env.example); jego wartości `CHANGE_ME` trzeba zastąpić przed uruchomieniem.
- Backend ma role `PROCESS_ROLE=combined|api|worker`. Domyślna rola to `combined`; rozdzielenie API i workerów jest opcją wdrożeniową, nie opisem potwierdzonego stanu hosta.
- Timer backupu tworzy dump PostgreSQL, metadane i sumę kontrolną. Kopia poza VM i materiały odzyskiwania są opisane w [ORACLE_OFF_VM_BACKUP.md](docs/ORACLE_OFF_VM_BACKUP.md). O powodzeniu odzyskiwania decyduje próba restore, nie samo istnienie dumpa.

### Wdrożenie i sprawdzenie wersji

Samo połączenie PR z `main` nie wdraża każdego commita na Oracle. Workflow [Deploy Oracle candidate](.github/workflows/oracle-deploy.yml) przyjmuje **dokładny 40-znakowy SHA należący do `main`** i adres API. Buduje obraz, wykonuje migracje, restartuje usługę oraz sprawdza `/health`, `/ready` i audyt runtime. Przy błędzie lokalnych kontroli skrypt może przywrócić poprzedni obraz; **nie cofa automatycznie migracji bazy**.

Wymagane GitHub Secrets: `ORACLE_SSH_HOST`, `ORACLE_SSH_USER`, `ORACLE_SSH_PRIVATE_KEY`, `ORACLE_SSH_KNOWN_HOSTS`. Klucz hosta jest przypięty, a SSH używa ścisłej weryfikacji. [Roll out approved Oracle release](.github/workflows/deploy-approved-oracle.yml) uruchamia wdrożenie po udanym workflow numeracji tylko dla zmiany oznaczonej `[deploy-oracle]`.

Po wdrożeniu sprawdź:

```bash
curl -fsS https://bezpieczna-polska-api.duckdns.org/health
curl -fsS https://bezpieczna-polska-api.duckdns.org/ready
curl -fsS https://bezpieczna-polska-api.duckdns.org/v1/sources
```

`/health.buildSha` musi odpowiadać wybranemu wydaniu; `/ready` potwierdza gotowość bazy i PostGIS. Zdrowie źródeł i rzeczywiste otrzymanie push trzeba sprawdzić oddzielnie. Przegląd publicznego API 6.10.2026 potwierdził środowisko `production` i gotowość PostgreSQL/PostGIS; nie był pełnym audytem hosta ani testem powiadomień.

### Railway i przejście klientów

Zapis migracji opisuje Oracle jako aktywnego nadawcę push i wyłączenie automatycznej wysyłki Railway. Utrzymuj **jednego aktywnego nadawcę**: `ENABLE_PUSH_DISPATCH=true` na wybranym backendzie, `false` na równoległym kandydacie. Flaga `false` pozostawia rejestrację urządzeń i autoryzowany ręczny test; wyłącza automatyczną wysyłkę kolejki.

`PRODUCTION_API_BASE_URL` i `PREVIEW_API_BASE_URL` są konfiguracją **nowych buildów**. Zmiana zmiennej nie przełącza już zainstalowanego APK, a zmiana hosta API wymaga uwzględnienia rejestracji push, bazy i klucza szyfrowania tokenów. Railway nie jest automatycznie aktualnym failoverem Oracle. Instrukcje pierwszego uruchomienia i równoległego etapu migracji znajdują się w [runbooku Oracle](docs/ORACLE_CUTOVER_RUNBOOK.md); jego zalecenia dla kandydata należy odróżnić od zakończonych kroków zapisanych w audytach.

[Skrypty Oracle](infra/oracle/README.md) · [Dostęp SSH](docs/ORACLE_ACCESS_CHECKLIST.md) · [Wydanie produkcyjne](docs/PRODUCTION_RUNBOOK.md)

## Firebase — konfiguracja i powiadomienia Android

Push wymaga **konfiguracji klienta w APK oraz konfiguracji nadawcy na backendzie**. Poprawnie działająca mapa lub odpowiedź `/health` nie potwierdza gotowości FCM.

### Konfiguracja klienta

Flutter inicjalizuje Firebase z wartości przekazanych przez `--dart-define`. Samo dodanie `google-services.json` nie zastępuje tego sposobu konfiguracji w obecnym kodzie.

| Wartość builda / GitHub Variable | Znaczenie |
| --- | --- |
| `FIREBASE_API_KEY` | Klucz konfiguracji aplikacji Firebase |
| `FIREBASE_PROJECT_ID` | Identyfikator projektu Firebase |
| `FIREBASE_MESSAGING_SENDER_ID` | Numer nadawcy FCM |
| `FIREBASE_ANDROID_APP_ID` | Identyfikator aplikacji Firebase używany przez preview |
| `FIREBASE_PRODUCTION_ANDROID_APP_ID` | Osobny identyfikator aplikacji Firebase dla production; workflow przekazuje go do builda jako `FIREBASE_ANDROID_APP_ID` |

Preview (`pl.bezpiecznapolska.preview`) i production (`pl.bezpiecznapolska`) mają osobne nazwy pakietów Android. Dobierz rejestrację aplikacji Firebase do budowanego kanału. Workflow production ma fallback do `FIREBASE_ANDROID_APP_ID`, ale sama obecność zmiennej nie dowodzi zgodności konfiguracji z pakietem produkcyjnym.

Te identyfikatory są konfiguracją klienta dołączaną do APK. **Prywatny klucz konta serwisowego nie może trafić do APK, README ani repozytorium.** Bez kompletu czterech wartości klienta adapter Firebase nie inicjalizuje się i aplikacja nie uzyska tokenu FCM.

### Konfiguracja backendu Oracle

| Zmienna w `backend.env` | Znaczenie |
| --- | --- |
| `FCM_SERVICE_ACCOUNT_JSON` | JSON konta serwisowego zawierający `project_id`, `client_email` i `private_key`; backend używa OAuth i FCM HTTP v1 |
| `PUSH_TOKEN_ENCRYPTION_KEY` | 32-bajtowy klucz kodowany jako 64 znaki hex albo base64; służy do szyfrowania tokenów w bazie |
| `ENABLE_PUSH_DISPATCH` | `true` — automatyczna wysyłka; `false` — rejestracja i ręczny test bez automatycznej wysyłki |
| `ENABLE_INGESTION` | Steruje cyklicznym pobieraniem źródeł; jego wyłączenie zatrzymuje automatyczny dopływ nowych danych |

Konto serwisowe nadawcy i konfiguracja aplikacji muszą umożliwiać wysyłkę do tego samego projektu FCM. JSON w pliku env przechowuj w jednej linii, z zachowaniem `\n` w `private_key`, zgodnie ze wzorem konfiguracji. Przy przenoszeniu istniejącej bazy zachowaj zgodny klucz szyfrowania; losowa zamiana klucza uniemożliwi odczyt zapisanych tokenów. Zmiany env wymagają ponownego uruchomienia usługi.

Backend ustala czas wygaśnięcia powiadomienia, ponownie sprawdza aktualność wpisu kolejki przed wysłaniem i przekazuje `eventId` do klienta. Android obsługuje otwarcie konkretnego komunikatu oraz osobne kanały ważności. Stan `ACCEPTED` oznacza przyjęcie wiadomości przez dostawcę, nie potwierdzenie wyświetlenia jej na telefonie. Parametry APNs dotyczą osobnej ścieżki iOS i nie są wymagane dla Androida.

### Jak sprawdzić push

1. Zainstaluj APK z konfiguracją Firebase i właściwym adresem backendu; włącz powiadomienia w aplikacji i udziel zgody systemowej.
2. Dodaj obserwowane miejsce i ustaw kategorie oraz promień powiadomień.
3. Uruchom test powiadomień w aplikacji i potwierdź faktyczny odbiór na tym telefonie.
4. Sprawdź odbiór w pierwszym planie, w tle i po zamknięciu aplikacji; kliknięcie rzeczywistego ostrzeżenia powinno otworzyć odpowiedni komunikat.
5. Przy problemie sprawdź kanały powiadomień, ograniczenia baterii, rejestrację/token urządzenia, konfigurację FCM na backendzie i zgodność projektu Firebase w APK.

Ręczny test sprawdza transport. Nie zastępuje próby dopasowania rzeczywistego alertu do obserwowanego miejsca, jego czasu wygaśnięcia i kliknięcia. Podczas migracji potwierdź, że telefon rejestruje się na backendzie, który wysyła automatyczne ostrzeżenia.

### Który build zawiera Firebase

| Workflow | Konfiguracja Firebase Android |
| --- | --- |
| [Build preview APK and source live checks](.github/workflows/preview-apk.yml) | Przekazuje cztery wartości klienta; właściwy preview do testu push |
| [Build preview APK and offline regression](.github/workflows/regression-preview.yml) | Przekazuje cztery wartości klienta i wykonuje regresję |
| [Production infrastructure and release gate](.github/workflows/production-release.yml) | Build produkcyjny wymaga konfiguracji Firebase, podpisu, publicznej polityki prywatności i gotowego backendu |
| [Build installable test APK](.github/workflows/test-apk.yml) | Przekazuje cztery wartości Firebase; szybki instalowalny build z obsługą FCM |

Szczegóły wcześniejszego kontraktu: [ALPHA14_PUSH.md](docs/ALPHA14_PUSH.md). Aktualne zachowanie określają kod i workflow wybranego wydania.

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
