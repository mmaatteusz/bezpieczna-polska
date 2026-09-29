# Oracle Cloud — runbook pierwszego uruchomienia i migracji

Ten runbook wykonujemy dopiero po utworzeniu osobnej instancji OCI. Railway pozostaje produkcją i fallbackiem przez cały etap testowy.

## 1. Utworzenie VM

Docelowo:

- Ampere A1 / ARM64,
- Ubuntu 24.04,
- start: 1 OCPU / 4 GB RAM,
- boot volume około 100 GB,
- publiczny IPv4,
- SSH tylko kluczem,
- Security List/NSG: 22 z ograniczonego źródła, 80/443 publicznie,
- 5432 i 8080 niewystawione publicznie.

Po pierwszym logowaniu sprawdź:

```bash
uname -m
dpkg --print-architecture
nproc
free -h
df -h /
```

Oczekiwane: `aarch64` / `arm64`.

## 2. Bootstrap hosta

Na VM:

```bash
git clone https://github.com/mmaatteusz/bezpieczna-polska.git
cd bezpieczna-polska
sudo BP_DEPLOY_USER=ubuntu bash infra/oracle/bootstrap-host.sh
```

Po ponownym logowaniu:

```bash
sudo bash infra/oracle/verify-host.sh
```

Przed konfiguracją sekretów skrypt może ostrzec, że API/env jeszcze nie istnieją; część systemowa musi być zielona.

## 3. PostgreSQL/PostGIS

Wygeneruj silne hasło lokalnie i nie zapisuj go w repo:

```bash
sudo BP_DB_PASSWORD='TU_LOKALNE_SILNE_HASLO' bash infra/oracle/configure-database.sh
```

Sprawdź:

```bash
sudo -u postgres psql -d bezpieczna_polska -c 'SELECT PostGIS_Version();'
sudo ss -ltnp | grep 5432
```

Port 5432 ma być wyłącznie na `127.0.0.1`.

## 4. Konfiguracja backendu

```bash
sudo cp infra/oracle/backend.env.example /etc/bezpieczna-polska/backend.env
sudo chmod 600 /etc/bezpieczna-polska/backend.env
sudoedit /etc/bezpieczna-polska/backend.env
```

Wypełnij wartości z obecnej produkcji bez kopiowania ich do GitHub.

Nie uruchamiaj jeszcze cutoveru. Oracle ma działać równolegle.

## 5. DNS i HTTPS

Najbezpieczniej użyć osobnej nazwy testowej, np. `oracle-api.<domena>`, zanim docelowe `api.<domena>` zostanie przełączone.

Gdy DNS wskazuje na VM:

```bash
sudo bash infra/oracle/enable-tls.sh oracle-api.example.pl admin@example.pl
```

## 6. Eksport Railway

Na zaufanym komputerze z dostępem do produkcyjnego `DATABASE_URL`:

```bash
SOURCE_DATABASE_URL='postgresql://...' \
  bash infra/oracle/export-source-database.sh railway-production.dump
```

Powstają:

- `railway-production.dump`,
- `railway-production.dump.sha256`.

Przenieś oba pliki na Oracle kanałem SSH/SCP.

## 7. Restore na Oracle

Przed restore Oracle API ma być zatrzymane lub jeszcze niewdrożone.

```bash
sudo BP_ALLOW_DESTRUCTIVE_RESTORE=YES \
  /usr/local/sbin/bp-restore-source-database /tmp/railway-production.dump
```

Następnie:

```bash
sudo /usr/local/sbin/bp-restore-drill /tmp/railway-production.dump
```

Restore drill tworzy osobną tymczasową bazę, sprawdza PostGIS i wymagane tabele, a potem ją usuwa.

## 8. Wdrożenie konkretnego SHA

Do pierwszego wdrożenia użyj SHA z `main`, nie nazwy brancha.

Manualnie albo przez workflow `Deploy Oracle candidate`.

Po wdrożeniu na VM:

```bash
sudo bash infra/oracle/verify-host.sh
curl -fsS http://127.0.0.1:8080/health | jq
curl -fsS http://127.0.0.1:8080/ready | jq
```

`buildSha` musi być dokładnie wdrożonym SHA.

## 9. Porównanie baz

Z hosta mającego dostęp do obu baz:

```bash
SOURCE_DATABASE_URL='postgresql://railway/...' \
TARGET_DATABASE_URL='postgresql://oracle/...' \
  bash infra/oracle/compare-databases.sh
```

Tryb domyślny wymaga zgodnego schematu/PostGIS i raportuje różnice liczników jako ostrzeżenia, ponieważ Railway nadal ingestuje dane.

Dla zamrożonych baz/snapshotów:

```bash
BP_STRICT_COUNTS=YES \
SOURCE_DATABASE_URL='...' TARGET_DATABASE_URL='...' \
  bash infra/oracle/compare-databases.sh
```

## 10. Test równoległy

Na Oracle sprawdzamy co najmniej:

- `/health`,
- `/ready`,
- `/v1/sources`,
- snapshot/status,
- RCB, RSO, WCZK,
- IMGW,
- PAA,
- schronienia i nearest shelter,
- UkraineAlarm,
- NEPTUN,
- map layers/GeoJSON,
- FCM na realnym Androidzie.

Railway pozostaje aktywny.

Dodatkowo uruchamiamy workflow `Compare baseline and Oracle runtime`. Porównuje on równolegle stan, `errorCode`, czas odpowiedzi, liczbę elementów i świeżość synchronizacji dla kluczowych źródeł. Baseline jest parametrem i dziś wskazuje Railway; narzędzie nie jest związane z konkretnym dostawcą hostingu.

Szczególnie obserwujemy `RCB`, `RSO`, `IMGW_HYDRO` i `PAA`, ponieważ baseline Railway z 2026-09-29 miał dla nich wielominutową konwergencję i timeouty, podczas gdy niezależne live-checki GitHub Actions osiągały te upstreamy. Nie uznajemy tego za dowód problemu Railway, dopóki Oracle nie pokaże powtarzalnie lepszego wyniku w kilku rundach.

## 11. GitHub Actions

Dopiero po utworzeniu VM dodamy sekrety SSH potrzebne przez manualny workflow Oracle. Na tym etapie nadal NIE zmieniamy:

- `PRODUCTION_API_BASE_URL`,
- `PREVIEW_API_BASE_URL`.

Najpierw Oracle musi przejść pełny runtime audit pod osobnym adresem.

## 12. Cutover

Cutover jest osobnym etapem. Wymagania:

- zielony pełny runtime audit,
- poprawny `BUILD_SHA`,
- test push E2E,
- backup,
- udany restore drill,
- kilka dni równoległej obserwacji,
- Railway nadal dostępny do rollbacku.

Dopiero wtedy zmieniamy adres używany przez produkcyjne buildy.
