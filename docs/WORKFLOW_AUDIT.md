# Workflowy GitHub Actions

Przegląd plików na main: **4.10.2026**. Lista poniżej zastępuje historyczny
spis alpha.16.1; wyzwalacze pochodzą z YAML, nie z nazw dawnych etapów.
Filtry ścieżek, uprawnienia, wymagane zmienne i warunki jobów są w podlinkowanych
plikach. Nie jest to deklaracja, że wszystkie aktualne runy są zielone.

| Workflow | Wyzwalacze | Rola i ograniczenia |
| --- | --- | --- |
| [android-update-compat.yml](../.github/workflows/android-update-compat.yml) | push (`main`); PR (`main`); ręcznie | Dwa warianty tego samego preview na x86_64; to nie pełny test migracji publicznego APK. |
| [audit-production-runtime.yml](../.github/workflows/audit-production-runtime.yml) | push (`main`); status wdrożenia; harmonogram; ręcznie | Zdrowie produkcji i opcjonalnie tożsamość wdrożonego SHA. |
| [auto-bump-alpha.yml](../.github/workflows/auto-bump-alpha.yml) | push (`main`) | Monotoniczna alpha na main; uruchamia kolejne buildy/kontrole, nie publikuje automatycznie w Play. |
| [build.yml](../.github/workflows/build.yml) | ręcznie | Ręczny build powiązany z kontrolą backendu. |
| [deploy-approved-oracle.yml](../.github/workflows/deploy-approved-oracle.yml) | zakończenie workflow (`main`) | Wdrażanie po udanej zmianie zawierającej znacznik [deploy-oracle]; zwykły merge dokumentacji nie jest takim żądaniem. |
| [ios-ci.yml](../.github/workflows/ios-ci.yml) | PR (`main`); push (`main`); ręcznie | Osobna walidacja natywnego iOS; poza priorytetem Androida. |
| [oracle-deploy.yml](../.github/workflows/oracle-deploy.yml) | ręcznie | Wdrożenie określonego SHA; wymaga dostępu i kontroli endpointu. |
| [oracle-host-audit.yml](../.github/workflows/oracle-host-audit.yml) | ręcznie | Ręczny audyt hosta Oracle. |
| [oracle-infra-validate.yml](../.github/workflows/oracle-infra-validate.yml) | PR (`main`); push (`main`) | Kontrola skryptów infrastruktury Oracle. |
| [oracle-runtime-compare.yml](../.github/workflows/oracle-runtime-compare.yml) | ręcznie | Porównanie dwóch jawnie podanych API w kilku rundach; nie zmienia adresów ani wdrożenia. |
| [oracle-ssh-preflight.yml](../.github/workflows/oracle-ssh-preflight.yml) | ręcznie | Ręczna weryfikacja dostępu SSH. |
| [preview-apk.yml](../.github/workflows/preview-apk.yml) | PR (`main`); push (`stage/**`); ręcznie | Preview ARM64 i kontrola źródeł dla wybranych zmian; status źródła zależy od runtime. |
| [production-release.yml](../.github/workflows/production-release.yml) | PR (`main`); push (`main`); ręcznie | Pełna regresja; artefakty produkcyjne tylko na tag/manual i po spełnieniu warunków. |
| [rcb-stage.yml](../.github/workflows/rcb-stage.yml) | push (`main`, `stage/rcb-live`); PR; ręcznie | Regresja RCB. |
| [regression-preview.yml](../.github/workflows/regression-preview.yml) | PR (`main`); push (`main`); ręcznie | Regresja offline i budowa preview. |
| [repository-branch-hygiene.yml](../.github/workflows/repository-branch-hygiene.yml) | push (`main`); PR (`main`); ręcznie | Testy reguł; usuwanie zakończonych gałęzi poza PR. Zachowuje aktywną pracę. |
| [shelters-stage.yml](../.github/workflows/shelters-stage.yml) | push (`main`, `stage/shelters-psp`); PR; ręcznie | Regresja schronień PSP. |
| [test-apk.yml](../.github/workflows/test-apk.yml) | PR (`main`); ręcznie | Instalowalny testowy APK. |

## Co sprawdzać przed wydaniem

Pełny gate w production-release obejmuje backend z realnym PostGIS i klienta
Flutter. Udany build preview nie oznacza publikacji produkcyjnej, a udana
instalacja testowa nie zastępuje prób na fizycznym Androidzie. Nie usuwamy
workflowów tylko dlatego, że mają w nazwie słowo stage: RCB i schronienia
nadal dostarczają własne kontrole.

Gate produkcyjny wymaga publicznej polityki HTML. Kontrola oryginalnych APK
jest osobnym skryptem; emulatorowy workflow aktualizacji nadal nie dowodzi
pełnej migracji danych publicznego wydania. Aktualną kolejność prac opisuje
[ROADMAP.md](ROADMAP.md).
