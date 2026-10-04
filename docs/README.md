# Dokumentacja Bezpiecznej Polski

Zacznij od [głównego README](../README.md), a następnie od dokumentu odpowiadającego
Twojemu zadaniu. Stan kodu, wdrożenia i opublikowanego APK to odrębne rzeczy.

## Bieżąca praca

| Dokument | Zastosowanie |
| --- | --- |
| [ROADMAP.md](ROADMAP.md) | Priorytety Androida i kryteria zakończenia; odnośniki do aktywnych PR-ów |
| [PRODUCTION_RUNBOOK.md](PRODUCTION_RUNBOOK.md) | Środowiska, podpisy, wersje, testy i wydanie produkcyjne |
| [WORKFLOW_AUDIT.md](WORKFLOW_AUDIT.md) | Aktualny spis workflowów i ich wyzwalaczy |
| [REPOSITORY_MAINTENANCE.md](REPOSITORY_MAINTENANCE.md) | Utrzymanie PR-ów i bezpieczne sprzątanie gałęzi |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Zgłoszenia błędów, walidacja i zasady zmian |

## Infrastruktura i odzyskiwanie

- [ORACLE_CUTOVER_RUNBOOK.md](ORACLE_CUTOVER_RUNBOOK.md) — przejście klientów i backendu.
- [ORACLE_ACCESS_CHECKLIST.md](ORACLE_ACCESS_CHECKLIST.md) — dostęp i kontrola hosta.
- [ORACLE_OFF_VM_BACKUP.md](ORACLE_OFF_VM_BACKUP.md) — backup poza VM i odzyskiwanie konfiguracji.
- [infra/oracle/README.md](../infra/oracle/README.md) — katalog skryptów infrastruktury.
- [INFRASTRUCTURE_STATUS_2026-10-04.md](INFRASTRUCTURE_STATUS_2026-10-04.md) — zachowane zapisy konfiguracji i wcześniejszych audytów; nie bieżący monitoring.

## Architektura i dane

- [ARCHITECTURE.md](ARCHITECTURE.md) — model i decyzje projektowe; planowane moduły nie oznaczają implementacji.
- [SOURCES.md](SOURCES.md) — źródła i kontrakty; runtime zdrowia integracji jest pod `/v1/sources`.
- [VALIDATION.md](VALIDATION.md) i [validation/](validation/) — procedury i materiały walidacyjne.

## Dokumenty w otwartych PR-ach

Poniższe dokumenty są przygotowane na gałęziach roboczych i jeszcze poza `main`.

| PR | Materiały |
| --- | --- |
| [#144 — prywatność](https://github.com/mmaatteusz/bezpieczna-polska/pull/144/files) | Projekt polityki, mapa Data safety i rzeczywiste testy akceptacyjne Androida |
| [#143 — aktualizacja APK](https://github.com/mmaatteusz/bezpieczna-polska/pull/143/files) | Kontrola dwóch oryginalnych APK i procedura migracji danych |
| [#142 — backend](https://github.com/mmaatteusz/bezpieczna-polska/pull/142/files) | Pomiary pojemności, metryki i warunki wdrożenia zmian |

Po scaleniu należy dodać bezpośrednie odnośniki do plików i zaktualizować roadmapę.

## Historia etapów

Zachowujemy dotychczasowe ścieżki, aby nie zepsuć odnośników z PR-ów i audytów.
Dokumenty poniżej opisują dawny etap lub wyniki z konkretnego dnia, nie aktualny
status wszystkich funkcji i źródeł.

- Etapy funkcjonalne: [ALPHA11_WATCHED_LOCATIONS.md](ALPHA11_WATCHED_LOCATIONS.md),
  [ALPHA12_UKRAINE.md](ALPHA12_UKRAINE.md), [ALPHA13_NEPTUN.md](ALPHA13_NEPTUN.md),
  [ALPHA14_PUSH.md](ALPHA14_PUSH.md), [ALPHA15_OFFLINE.md](ALPHA15_OFFLINE.md),
  [ALPHA17_IMGW.md](ALPHA17_IMGW.md), [ALPHA18_SOURCE_AUDIT.md](ALPHA18_SOURCE_AUDIT.md).
- Dawne weryfikacje źródeł: [RCB_STAGE.md](RCB_STAGE.md),
  [SHELTERS_STAGE.md](SHELTERS_STAGE.md), [PAA_STAGE.md](PAA_STAGE.md),
  [CYBER_STAGE.md](CYBER_STAGE.md), [SG_STAGE.md](SG_STAGE.md),
  [POLICE_PSP_STAGE.md](POLICE_PSP_STAGE.md),
  [SECURITY_LEVELS_MAP_STAGE.md](SECURITY_LEVELS_MAP_STAGE.md).
- Audyty pokrycia: [WCZK_DEDUP_STAGE.md](WCZK_DEDUP_STAGE.md),
  [WCZK_REVERIFY_2026-09-25.md](WCZK_REVERIFY_2026-09-25.md),
  [AUDIT_2026-09-26.md](AUDIT_2026-09-26.md).
