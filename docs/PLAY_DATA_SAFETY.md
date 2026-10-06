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

Publiczna [polityka prywatności](PRIVACY_POLICY.md) obowiązuje od 6.10.2026.
Administrator: Mateusz Kawczyński; kontakt: mati66628@gmail.com. Opisuje
Oracle Frankfurt, Firebase, geokodowanie i ograniczenia usuwania danych beta.
Draft zachowano jako wcześniejszy materiał audytowy, nie obowiązującą politykę.

Domyślny URL buildów: https://github.com/mmaatteusz/bezpieczna-polska/blob/main/docs/PRIVACY_POLICY.md
Można go nadpisać repozytoryjnym `vars.PRIVACY_POLICY_URL`. Workflow sprawdza
HTTPS/HTML i przekazuje URL do klienta production. Ten check nie dowodzi
poprawności prawnej ani zgodności deklaracji Data safety. Dla konkretnego AAB
użyj adresu z `play-build-info.txt` — beta.3 przypina wersję polityki do commitu.
Ten sam adres wpisz w Play Console. W aplikacji: Ustawienia → Polityka prywatności.
Brak automatycznej retencji historii push oraz pełnego usunięcia przez samo
wyrejestrowanie pozostaje ograniczeniem beta; nie deklaruj takiego mechanizmu
w formularzu Google Play.

Źródła sprawdzone 4.10.2026:
- https://support.google.com/googleplay/android-developer/answer/10144311
- https://support.google.com/googleplay/android-developer/answer/10787469
- https://firebase.google.com/support/privacy
