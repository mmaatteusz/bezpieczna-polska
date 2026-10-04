# Google Play: robocza mapa Data safety

To analiza kodu, nie gotowa deklaracja do wysłania. Wypełnić dla rzeczywistego
produkcyjnego APK/AAB, konfiguracji SDK i wszystkich wersji nadal dostępnych
w Play. Formularz nie opisuje tylko ostatniej wersji.

| Dane / kategoria do oceny | Dowód w kodzie | Cel i trwałość | Co trzeba potwierdzić |
| --- | --- | --- | --- |
| Dokładna lokalizacja | `DataRepository.around`, `nearestShelters`; `PushManager._apiPreferences` | Funkcje aplikacji; punkty przy zapytaniu, trwałe miejsca w preferencjach push | Czy miejsca oznaczają lokalizację użytkownika; retencja push; logi proxy i SDK; nie oznaczać całej kategorii jako ephemeral |
| Przybliżona lokalizacja | Wybrane województwo wysyłane w preferencjach; oglądany obszar map | Dopasowanie informacji/push | Klasyfikacja konkretnych danych i ewentualne wnioskowanie lokalizacji z IP |
| Urządzenie lub inne identyfikatory | InstallationId, FCM token, Firebase Installations | Funkcjonalność push; trwałe na backendzie | SDK może generować identyfikatory przed zgodą na powiadomienia; nie deklarować automatycznie opcjonalności |
| Nazwy obserwowanych miejsc / inne treści użytkownika | `label` w liście push locations | Rozpoznanie zapisanych miejsc; trwałe przy kategorii push | Nazwa może zawierać adres lub dane osobowe; ustalić kategorię według rzeczywistego zastosowania |
| Interakcje i diagnostyka | Preferencje kategorii, rejestracja, wersja/platforma, kolejka wysyłek, metryki API | Funkcjonalność i bezpieczeństwo | Zakres logów produkcyjnych i danych SDK; brak Crashlytics nie oznacza braku wszelkiej diagnostyki |
| Dane wyłącznie lokalne | Ustawienia wyglądu, lokalny cache/offline | Nie są same w sobie zbieraniem poza urządzeniem | Sprawdzić wszystkie wywołania sieciowe i dostawców; allowBackup=false nie wyklucza wszystkich transferów OEM |

Nie deklarować „nie zbieramy danych”. Pseudonimowy installationId nadal może
podlegać ujawnieniu. Samo przetwarzanie chwilowe również ocenić według
aktualnej definicji Google, nie według braku tabeli w naszej bazie.

„Udostępnianie” nie jest synonimem każdego przekazania do usługodawcy:
Google przewiduje wyjątek dla podmiotu przetwarzającego wyłącznie na rzecz
wydawcy oraz niektórych transferów inicjowanych przez użytkownika. Ustalić
rolę Firebase, hostingu, map i nawigacji na podstawie warunków i konfiguracji.
Nie oznaczać „brak udostępniania” bez tego sprawdzenia.

HTTPS i brak cleartext w manifest są podstawą kontroli szyfrowania transmisji,
ale trzeba sprawdzić rzeczywiste endpointy produkcji, map i SDK. Wyrejestrowanie
push nie dowodzi pełnego usunięcia danych: potwierdzić mechanizm żądania,
retencję pozostałych rekordów i kopii przed deklaracją możliwości usuwania.

## Publikacja polityki

Uzupełnić `PRIVACY_POLICY_DRAFT.md`, potwierdzić tożsamość/kontakt administratora,
podstawy przetwarzania, hosting, transfery i realną retencję. Opublikować jako
publiczną stronę HTML bez logowania i ograniczenia regionów — nie jako PDF.
Ustawić repozytoryjne `vars.PRIVACY_POLICY_URL`; workflow sprawdza odpowiedź
HTTPS/HTML i przekazuje URL do AAB i APK. Klient production wymaga poprawnego
URL przy starcie. Ten check nie dowodzi poprawności prawnej ani treści strony.
Wpisać ten sam URL w Play Console; w aplikacji: Ustawienia → Polityka prywatności.

Źródła sprawdzone 4.10.2026:
- https://support.google.com/googleplay/android-developer/answer/10144311
- https://support.google.com/googleplay/android-developer/answer/10787469
- https://firebase.google.com/support/privacy
