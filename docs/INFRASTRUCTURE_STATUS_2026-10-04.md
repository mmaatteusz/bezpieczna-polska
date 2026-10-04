# Zapis infrastruktury i audytów — przegląd 4.10.2026

Przeniesiono z dotychczasowego README przy porządkowaniu repozytorium.
Poniższe wyniki pochodzą z wcześniejszych audytów i opisów wdrożenia.
Nie wykonywano nowego audytu hosta w ramach zmiany dokumentacji; nie należy
traktować tych wpisów jako potwierdzenia dzisiejszego stanu usług.
Bieżące instrukcje: [runbook Oracle](ORACLE_CUTOVER_RUNBOOK.md),
[backup i odzyskiwanie](ORACLE_OFF_VM_BACKUP.md).

### Ostatni potwierdzony audyt migracji

Podczas audytu 30.09–01.10.2026 uzyskano `ORACLE_HOST_AUDIT_PASS` i `PROBE_ALL_OK`. Smoke test potwierdził kontrakty krytycznych źródeł RCB, RSO, LEVELS, SHELTERS, IMGW METEO/HYDRO, PAA, UA i NEPTUN, odpowiedzi API mapy i schronień oraz odświeżenie NEPTUN.

Znane ograniczenia z tego audytu:

| Źródło | Stan | Szczegóły |
|---|---|---|
| SHELTERS | DEGRADED | `SHELTER_FALLBACK_OLDER_THAN_LAST_GOOD`; zachowano 86 388 obiektów, data źródłowa 21.09.2026 |
| WCZK-18 | BROKEN | `WCZK_HTML_CONTRACT_CHANGED`; adapter wymaga dostosowania |

Przejście smoke testu uwzględnia dopuszczoną ostatnią poprawną kopię schronień. Nie oznacza, że wszystkie źródła są zdrowe. Powyższe wyniki są zapisem audytu, a nie obietnicą bieżącej dostępności.

## Backend na Oracle Cloud

Docelowy adres nowych buildów Android:

**https://bezpieczna-polska-api.duckdns.org**

| Element | Konfiguracja |
|---|---|
| Region | OCI Frankfurt |
| Host | Ubuntu 24.04 ARM64, VM.Standard.A1.Flex |
| Zasoby | 1 OCPU, 6 GB RAM, boot volume około 100 GB |
| API | Node.js 24, TypeScript, Fastify, Docker |
| Reverse proxy | nginx i HTTPS z automatycznym odnowieniem certyfikatu |
| Baza | PostgreSQL 17 i PostGIS 3.6 |
| Publiczne porty | 80 i 443; SSH 22 ograniczany administracyjnie w OCI |
| Prywatne porty | PostgreSQL 5432 i API 8080 nie są otwarte publicznie |

PostgreSQL nasłuchuje na localhost. Aplikacja korzysta z roli `bp_app` bez uprawnień superuser. nginx obsługuje HTTPS i przekazuje ruch do prywatnego API. Sekrety hosta są przechowywane poza repozytorium z ograniczonymi uprawnieniami.

Migracja obejmuje sprawdzenie architektury, przypięcie klucza hosta SSH, preflight, audyt usług i sieci, odtworzenie bazy oraz testy API. Szczegóły: [Oracle cutover runbook](ORACLE_CUTOVER_RUNBOOK.md).

### Railway w okresie przejściowym

Railway pozostaje uruchomiony dla okresu przejściowego i starszych buildów. Automatyczna wysyłka push została tam wyłączona; na Oracle została włączona po porównaniu rejestracji urządzeń i historii wysyłki.

Porównanie potwierdziło: brak urządzeń obecnych wyłącznie na Railway, brak nowszych rejestracji Railway, brak różnic porównanej historii push i zgodność klucza szyfrowania tokenów.

Zmiana adresu w GitHub Variables wpływa na **nowe buildy**. Nie zmienia adresu zapisanego w już zainstalowanym APK. Railway i Oracle nie mają automatycznej replikacji baz, więc Railway nie jest automatycznie aktualnym zapasowym backendem. Wyłączenie usług Railway wymaga zakończenia przejścia klientów i sprawdzenia pozostałych zależności.

## Backup i odzyskiwanie bez komputera autora

- Codzienny timer tworzy dump PostgreSQL, metadane i SHA-256.
- Hook wysyła kopię poza VM do prywatnego OCI Object Storage przez instance principals.
- Uprawnienia VM do obiektów backupu umożliwiają tworzenie i inspekcję, bez odczytu, nadpisywania i usuwania.
- Wymagany upload poza VM jest częścią powodzenia zadania backupu.
- Kopię pobraną z Object Storage sprawdzono sumą SHA-256 i odtworzono w izolowanej bazie: schema 2, 31 źródeł, 86 388 schronień.
- Zaszyfrowany pakiet konfiguracji hosta wykorzystuje Scrypt i AES-256-GCM. Pobraną kopię odszyfrowano i zweryfikowano bez wypisywania sekretów.
- Zdalną kopię klucza SSH zabezpieczono hasłem i potwierdzono logowanie.
- Zdalną kopię klucza upload Android zabezpieczono hasłem i potwierdzono poprawność keystore.

Hasła odzyskiwania muszą być dostępne w niezależnym menedżerze haseł. GitHub Secrets służą CI i nie pozwalają później pobrać ich wartości jako kopii odzyskiwania. Po zmianie konfiguracji lub wdrożenia należy odświeżyć pakiet odzyskiwania.

Testy komponentów odzyskiwania nie zastępują pełnego ćwiczenia odtworzenia nowej VM. Do dalszego dopracowania pozostają monitoring backupów, retencja oraz pełny test awarii hosta.

Instrukcje: [Backup poza VM i odzyskiwanie](ORACLE_OFF_VM_BACKUP.md).

