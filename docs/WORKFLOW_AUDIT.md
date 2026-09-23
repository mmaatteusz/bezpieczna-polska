# Przegląd workflowów — alpha.16.1

Stan z dostępnej kopii alpha.16. Potwierdzić zdalne wyzwalacze i checks na `main` przed usuwaniem czegokolwiek.

| Plik | Automatycznie na `main` / PR do `main` | Powód zachowania |
|---|---|---|
| `production-release.yml` | Tak / tak | Pełna regresja z PostGIS, migracje/restore, kontrakty, release gate i podpis Androida (release tylko tag/manual + prawdziwe dane). |
| `alpha15-preview.yml` | Tak / tak | Buduje osobny arm64 preview APK; pełna regresja offline, NEPTUN i push. Nazwa pliku historyczna, nazwa jobu już alpha.16. |
| `rcb-stage.yml` | Tak dla zmian backend/mobile; PR także | Niezależna regresja RCB. |
| `shelters-stage.yml` | Tak dla zmian backend/mobile; PR także | Niezależna regresja PSP; live PSP jest opcjonalne z powodu 403. |
| `build.yml` | Nie, tylko manualnie | Build preview po sprawdzeniu faktycznie wdrożonego backendu i zsynchronizowanych RCB/PSP. |
| `alpha11-preview.yml` | Nie; PR tylko do historycznego `stage/police-psp-incidents` | Historyczny preview obserwowanych miejsc. |
| `preview-apk.yml` | Nie; PR tylko do historycznego `stage/sg-border` | Historyczny preview Policja/PSP. |
| `levels-stage.yml` | Nie; push do historycznego `stage/security-levels` i pliku importu | Historyczna weryfikacja stopni alarmowych. |
| `probe-shelters.yml` | Nie; push do historycznego `stage/quality-pass` | Historyczna diagnostyka serwera PSP. |

Usunięto `alpha14-preview.yml`: był tylko ręczny, oczekiwał `versionName=0.1.0-alpha.14` i `versionCode=2014`, więc uruchomienie na `main` alpha.16 kończyłoby się błędem. Jego unikalne testy NEPTUN/push oraz budowę preview obejmuje `alpha15-preview.yml` (obecnie alpha.16), a pełny gate obejmuje `production-release.yml`.

Pozostałe workflowy zachowano: główna ścieżka alpha.16 i niezależne regresje nadal mają uzasadnienie, a ręczne/historyczne nie wpływają na checks `main`. Ewentualne dalsze archiwizowanie wymaga potwierdzenia rzeczywistego stanu zdalnego repozytorium.
