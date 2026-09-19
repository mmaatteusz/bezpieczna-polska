# Stan kontynuacji — etap RCB

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
