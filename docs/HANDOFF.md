# Stan kontynuacji — etap PSP/dane.gov.pl

Repozytorium prywatne: https://github.com/mmaatteusz/bezpieczna-polska.
Alpha.2 została zbudowana: Actions run 35398119623 zakończony sukcesem.
Użytkownik potwierdził publikację kodu i kompilację w tym repozytorium.
Konektor GitHub zwraca 404; zalogowana przeglądarka ma dostęp.

Obecny etap alpha.3: RCB + PostGIS + /status + sourceHealth + konfiguracja
buildu, bez redesignu. Szczegóły: RCB_STAGE.md. Kolejność źródeł w tym pliku.
Nie implementować pozostałych źródeł równocześnie.

Nie ma wdrożonego publicznego backendu ani domeny. Nie zastępować ich
fikcyjnym URL, GitHub Actions ani ustawieniem ręcznym u użytkownika.
Wdrożenie wymaga wskazania docelowego hosta/domeny i dostępu.
Stary workflow alpha.2 nie jest ścieżką wydania alpha.3.

Nie instalować ponownie lokalnego Android SDK; CI ma potrzebne narzędzia.
Lokalnie Node.js 24, brak Flutter i serwera PostGIS. Test PostGIS wymaga
TEST_DATABASE_URL do bazy testowej, a nie bazy produkcyjnej.

Etap PSP zaimplementowany: docs/SHELTERS_STAGE.md. Adapter i zakładka schronienia zachowują istniejący UI. Po PSP następne są stopnie alarmowe RP. Nie uruchamiać pozostałych integracji równolegle.

## Zapisany stan PSP — 2026-09-20

- Draft PR #2: https://github.com/mmaatteusz/bezpieczna-polska/pull/2
  (stage/shelters-psp → stage/rcb-live; etap RCB pozostaje osobnym PR #1).
- Zdalny commit implementacji: fa264f0de7506318889b0827eb380f7d3d3a28ed.
  Workflow tylko do weryfikacji: a394965e7bb4c9cd0839ccfd01b17f95767c71e5.
- Końcowy CI PSP: https://github.com/mmaatteusz/bezpieczna-polska/actions/runs/35491689466
  Testy backendu/PostGIS, Flutter analyze i testy Flutter zakończone sukcesem.
  CI regresji RCB: https://github.com/mmaatteusz/bezpieczna-polska/actions/runs/35491689476
  również zakończony sukcesem. PR pokazał 3 successful checks, 2 skipped;
  pominięte zadania live-source nie oznaczają poprawnej synchronizacji PSP.
- Rzeczywisty import w bieżącym środowisku: 2026-09-20 05:17 UTC,
  85 889 punktów krajowych, 4 064 kujawsko-pomorskich, 449 wyników Bydgoszcz.
  Dowód: docs/validation/shelters/shelters-live.json.
- Dostęp PSP z GitHub Actions nadal blokowany HTTP 403 (XML i CSV),
  metadane dane.gov.pl odpowiadają HTTP 200. Dowód diagnostyczny:
  https://github.com/mmaatteusz/bezpieczna-polska/actions/runs/35491250947
  Nie obchodzić blokady ani nie uznawać zielonego CI kodu za dowód live importu.
  Nie używać niespójnej kopii tabular_data jako automatycznego fallbacku.
- Nowego APK z działającym publicznym backendem nie wydano. Potrzebny
  docelowy host/domena z dostępem do PSP; bramka wydania wymaga zdrowych RCB i PSP.
- Historia lokalna różni się od zdalnej; nie force-pushować lokalnego main.
  CI sformatował pliki Dart zdalnie. Kolejne zmiany opierać na zdalnej gałęzi.
