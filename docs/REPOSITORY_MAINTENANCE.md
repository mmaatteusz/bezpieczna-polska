# PR-y i gałęzie — zasady utrzymania

## Aktualne PR-y

Przegląd z 4.10.2026. To lista pracy, a nie potwierdzenie scalenia lub wdrożenia.

| PR | Zakres | Dlaczego pozostaje otwarty |
| --- | --- | --- |
| [#139](https://github.com/mmaatteusz/bezpieczna-polska/pull/139) | Ostrzeżenia push | Aktualna poprawka P0, integracja i test urządzenia |
| [#141](https://github.com/mmaatteusz/bezpieczna-polska/pull/141) | Lokalna sytuacja na Start | Aktualna poprawka P0, jeszcze poza main |
| [#144](https://github.com/mmaatteusz/bezpieczna-polska/pull/144) | Prywatność i testy użytkowników | Draft; brak finalnej polityki i testów na telefonach |
| [#142](https://github.com/mmaatteusz/bezpieczna-polska/pull/142) | Backend przed większym ruchem | Draft; realny PostGIS i pomiary przed wdrożeniem |
| [#143](https://github.com/mmaatteusz/bezpieczna-polska/pull/143) | Aktualizacja wydania APK | Kontrola artefaktów i procedura; test danych pozostaje do wykonania |
| [#140](https://github.com/mmaatteusz/bezpieczna-polska/pull/140) | Daty fixture schronień | Osobna poprawka testów; wymaga integracji z nowszym main |
| [#123](https://github.com/mmaatteusz/bezpieczna-polska/pull/123) | Kontrakt wdrożenia niezależny od dostawcy | Unikalna zmiana, wymaga przeglądu konfiguracji i konfliktów |
| [#128](https://github.com/mmaatteusz/bezpieczna-polska/pull/128) | Porównanie równoległych backendów | Dodaje osobny workflow i skrypt; nie jest w main |
| [#119](https://github.com/mmaatteusz/bezpieczna-polska/pull/119) | Wariant ikon NEPTUN | Oddzielny projekt wizualny; nie należy traktować go jako scalonego |

## Propozycje zastąpione podczas przeglądu

| Starszy PR | Następca / obecne rozwiązanie |
| --- | --- |
| #75 — GNSS | #76, #77 i obecna warstwa GPSJAM |
| #81 — ekran ładowania | #82 i obecny BootstrapApp/BrandLoadingScreen |
| #90 — synchronizacja schronień | Draft #142; nie oznacza, że optymalizacja jest już wdrożona |
| #97 — worker UkraineAlarm | #96 i późniejsze zmiany na main |
| #100 — kontrakt UkraineAlarm | #98 oraz #110 |
| #106 — diagnostyka kolejności UkraineAlarm | #107, #110 i obecny adapter |
| #120 — legenda | Scalony #130 |
| #122 — plan Oracle w README | Aktualne README, roadmapa i runbooki |

Zamknięcie oznacza zakończenie starszej propozycji, nie jej scalenie. Powód
pozostaje w opisie PR, a kod w historii i referencji PR. Gałąź można usunąć
po upewnieniu się, że nie zawiera późniejszych zmian.

## Automatyczne sprzątanie gałęzi

Workflow [Repository branch hygiene](../.github/workflows/repository-branch-hygiene.yml)
uruchamia testy reguł. Na PR nie usuwa gałęzi. Na `main` lub przy manualnym
uruchomieniu czyta aktualne gałęzie oraz otwarte i zamknięte PR-y.

Zawsze zachowuje:

- domyślną gałąź i gałęzie chronione;
- gałęzie otwartych PR-ów w tym repozytorium, również draftów;
- gałęzie z nowymi commitami po zamknięciu/scaleniu PR;
- pracę, której zakończenia nie da się wykazać z powodu błędu API.

Usunięcie wymaga jednego z dowodów:

1. Dokładny SHA gałęzi jest headem PR scalonego do domyślnej gałęzi, także przy squash merge.
2. Commit gałęzi jest przodkiem obecnego `main` lub jest z nim identyczny.
3. Gałąź i dokładny SHA są na [liście przejrzanych nieaktualnych propozycji](../scripts/repository-obsolete-branches.json), a wskazany PR jest zamknięty.

Bezpośrednio przed usunięciem ponownie sprawdzane są otwarte PR-y i SHA.
Workflow zapisuje w summary nazwy, SHA i przyczyny usunięcia oraz listę
zachowanych gałęzi. Tagi, wydania i artefakty nie podlegają tej automatyzacji.
Samo sprzątanie nie zmienia hostingu, sekretów ani adresów API.

## Odtworzenie pracy

Kod zamkniętego PR można przywrócić lokalnie z referencji PR:

```bash
# Zastąp 120 numerem właściwego PR
 git fetch origin refs/pull/120/head:restore/pr-120
 git switch restore/pr-120
```

Dla gałęzi scalonej kod pozostaje również w historii main. Usunięcie starej
gałęzi nie jest powodem do scalania funkcji bez przeglądu i wymaganych testów.
