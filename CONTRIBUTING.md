# Praca nad Bezpieczną Polską

Punktem wyjścia jest aktualny `main`. Android ma pierwszeństwo; zmiany iOS
nie powinny blokować pracy nad Androidem.

## Zgłoszenie błędu

Podaj wersję aplikacji i build, kanał (preview/production), model telefonu,
Android, kroki odtworzenia oraz oczekiwany i rzeczywisty wynik. Przy problemie
z danymi dodaj region, źródło i czas komunikatu. Pomocny jest zrzut ekranu,
ale zasłoń dokładną lokalizację i inne prywatne informacje.

Nie publikuj tokenów FCM, sekretów instalacji, kluczy Firebase Admin,
keystore, haseł, `google-services.json` ani danych dostępowych hosta.
Zgłoszenia nie zastępują kontaktu z numerem 112 w nagłym zagrożeniu.

## Zmiana kodu

1. Pobierz aktualny `main` i utwórz gałąź `fix/…`, `feat/…`, `docs/…` lub `infra/…`.
2. Zrób jedną spójną zmianę. Sprawdź jej zachowanie i ograniczenia.
3. Uruchom odpowiednie kontrole lokalne oraz wymagane CI.
4. W PR opisz problem, wynik zmiany, walidację i niewykonane testy.
5. Użyj draftu, jeśli brakuje konfiguracji, testów urządzenia lub warunków wdrożenia.

Backend: `npm run build` i właściwe testy w `backend/`. Klient: `dart format`,
`flutter analyze` i właściwe testy w `mobile/`. Testy wymagające PostGIS
uruchamiaj z testową bazą, nigdy z bazą produkcyjną.

Nie zmieniaj podpisu APK, nazw pakietów ani produkcyjnych adresów API w ramach
zwykłego porządkowania. Migracje bazy muszą być opisane, z kontrolą backupu
oraz sposobu odzyskiwania. Nowy przepływ danych użytkownika wymaga aktualizacji
polityki prywatności i Data safety.

## Wersje i dokumentacja

Numer wersji pochodzi z `backend/package.json` i `mobile/pubspec.yaml`.
`node scripts/sync-mobile-version.mjs --check` sprawdza zgodność.
Na `main` workflow automatycznie podbija alphę; zachowaj znaczniki wersji
README i runbooka obsługiwane przez `scripts/bump-alpha.mjs`.

Nie wpisuj przygotowanej funkcji jako gotowej przed scaleniem. Odróżniaj
kod, build, wdrożenie i próbę na telefonie. Informacja „FCM przyjął wiadomość”
nie oznacza „użytkownik ją zobaczył”.

Aktualizuj [indeks dokumentacji](docs/README.md) i [roadmapę](docs/ROADMAP.md).
Audyty historyczne zachowuj z datą; bieżących instrukcji nie zastępuj wynikiem
starego smoke testu. Porządek gałęzi opisuje
[REPOSITORY_MAINTENANCE.md](docs/REPOSITORY_MAINTENANCE.md).
