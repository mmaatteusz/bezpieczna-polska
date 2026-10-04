# PR-y i gałęzie — zasady utrzymania

## Wspólna integracja

Poprawki z 17 PR-ów połączono w jedną historię i wspólny kod aplikacji.
Numery PR-ów oznaczają zestawy zmian, a nie osobne zainstalowane aplikacje.
Opis wkładu każdej zmiany oraz rozstrzygnięć konfliktów:
[PR_INTEGRATION_2026-10-04.md](PR_INTEGRATION_2026-10-04.md).

PR-y pozostają otwarte do rzeczywistego scalenia ich commitów. Ich historii
nie zastępuje zamknięcie z powodu podobnego zakresu lub wieku gałęzi.
Dalsze zadania urządzeń, prywatności i wdrożenia są w [roadmapie](ROADMAP.md).

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
