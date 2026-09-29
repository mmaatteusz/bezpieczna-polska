# Oracle Cloud A1 — przygotowanie produkcji

Ten katalog przygotowuje równoległą instancję produkcyjną Bezpiecznej Polski na OCI bez przełączania obecnej produkcji Railway.

## Docelowy układ

Jedna maszyna `VM.Standard.A1.Flex` w home region:

- Ubuntu 24.04 ARM64,
- budżet Always Free: do 2 OCPU / 12 GB RAM; start operacyjny: 1 OCPU / 4 GB RAM,
- 100 GB boot volume na start (z 200 GB puli Always Free pozostaje zapas),
- po uruchomieniu monitorować CPU, RAM i sieć w OCI; A1 może zostać odzyskana jako idle, jeśli przez 7 dni wszystkie progi wykorzystania pozostają poniżej 20%,
- nie generować sztucznego ruchu/obciążenia tylko po to, by omijać mechanizm idle; zamiast tego dobrać rozmiar VM do realnego zużycia,
- PostgreSQL 17 + PostGIS natywnie na ARM64,
- API budowane z istniejącego `backend/Dockerfile`,
- kontener API uruchamiany przez systemd z `--network host`,
- API nasłuchuje wyłącznie na `127.0.0.1:8080`,
- PostgreSQL nasłuchuje wyłącznie na `127.0.0.1:5432`,
- Nginx wystawia tylko 80/443,
- TLS przez Certbot,
- codzienny lokalny backup + ręczny restore drill,
- Railway pozostaje aktywny aż do pełnego cutoveru.

## Sieć OCI

Security List / NSG:

- TCP 22: najlepiej tylko z zaufanego adresu administracyjnego,
- TCP 80: publicznie,
- TCP 443: publicznie,
- NIE otwierać TCP 5432,
- NIE otwierać TCP 8080.

UFW na VM jest konfigurowany przez `bootstrap-host.sh`, ale reguły OCI nadal trzeba ustawić w konsoli.

Szczegółowy runbook pierwszego uruchomienia i migracji znajduje się w [`docs/ORACLE_CUTOVER_RUNBOOK.md`](../../docs/ORACLE_CUTOVER_RUNBOOK.md).

Po uruchomieniu kandydata Oracle użyj także manualnego workflow `Compare baseline and Oracle runtime`, aby porównać źródła i czasy synchronizacji 1:1 z aktualną produkcją.

## Kolejność

1. Utwórz VM A1 z Ubuntu ARM64.
2. Sklonuj repo lub wgraj katalog `infra/oracle`.
3. Uruchom:
   ```bash
   sudo BP_DEPLOY_USER=ubuntu bash infra/oracle/bootstrap-host.sh
   ```
4. Utwórz bazę:
   ```bash
   sudo BP_DB_PASSWORD='MOCNE_HASLO' bash infra/oracle/configure-database.sh
   ```
5. Skopiuj `backend.env.example` do `/etc/bezpieczna-polska/backend.env`, uzupełnij sekrety i ustaw chmod 600.
6. Gdy DNS wskazuje już na VM:
   ```bash
   sudo bash infra/oracle/enable-tls.sh api.twojadomena.pl admin@twojadomena.pl
   ```
7. Wyeksportuj źródłową bazę przez `export-source-database.sh`, przenieś dump na Oracle i wykonaj kontrolowany restore przez `restore-source-database.sh`.
8. Wdróż konkretny commit przez `deploy-release.sh` lub manualny workflow Oracle.
9. Wykonaj testy `/health`, `/ready`, źródeł oraz restore drill.
10. Dopiero po stabilnym teście równoległym zmieniamy URL-e aplikacji.

## Ważne

Ten etap NIE:
- wyłącza Railway,
- nie zmienia `PRODUCTION_API_BASE_URL`,
- nie zmienia `PREVIEW_API_BASE_URL`,
- nie otwiera PostgreSQL do Internetu,
- nie kopiuje sekretów do repo.

Pełny runtime audit zostanie podpięty do workflow Oracle po scaleniu provider-neutral PR #123.
