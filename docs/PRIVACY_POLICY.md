# Polityka prywatności — Bezpieczna Polska

Obowiązuje od 6 października 2026 r. Dotyczy aplikacji Android Bezpieczna Polska, w tym wydania beta 0.1.0-beta.3.

## Administrator i kontakt

Administratorem danych jest Mateusz Kawczyński. W sprawach prywatności, dostępu do danych i ich usunięcia napisz na **mati66628@gmail.com**.

Bezpieczna Polska jest niezależną aplikacją informacyjną. Nie wymaga założenia konta. Rejestracja powiadomień korzysta z technicznego identyfikatora instalacji, a nie imienia, numeru telefonu lub adresu e-mail użytkownika.

## Dane i cele przetwarzania

- **Ustawienia na telefonie:** województwo, miejscowość i wskazane współrzędne, obserwowane miejsca (nazwy, punkty i promienie), preferencje map, wyglądu i powiadomień oraz cache i pakiety offline. Służą zapamiętaniu wyborów i korzystaniu z zapisanych informacji bez internetu.
- **Lokalizacja:** po użyciu odpowiedniej funkcji aplikacja prosi Androida o lokalizację. Możesz odmówić i wskazać miejscowość ręcznie. Współrzędne wysyłane są do API przy wyszukiwaniu informacji w okolicy i najbliższych schronień. Aplikacja nie prowadzi ciągłego śledzenia w tle; te zapytania API nie tworzą historii przemieszczania. Wyszukiwanie miejsc i rozpoznawanie województwa korzysta również z systemowej usługi geokodowania Androida, która może otrzymać wpisany adres lub współrzędne.
- **Powiadomienia:** serwer przechowuje identyfikator instalacji, platformę, zaszyfrowany token Firebase Cloud Messaging (FCM), wersję aplikacji, język, województwo, wybrane kategorie, status rejestracji i daty aktywności. Jeśli włączysz powiadomienia dla obserwowanych miejsc, przesyłane są także ich nazwy, współrzędne i promienie. Bez tej kategorii lista miejsc przesyłana z preferencjami jest pusta. Dane służą dopasowaniu i wysyłaniu komunikatów.
- **Obsługa wysyłki:** kolejka serwera przechowuje identyfikator instalacji, komunikat i jego rewizję, kategorię i treść powiadomienia, daty prób, wyniki oraz techniczne kody błędów. Przyjęcie komunikatu przez FCM nie oznacza, że został wyświetlony na telefonie.
- **Dane połączenia:** infrastruktura serwera otrzymuje adres IP i dane żądania. Log API obejmuje trasę, status i czas odpowiedzi bez treści żądania. Serwer pośredniczący i dostawcy infrastruktury mogą przechowywać IP, czas, ścieżkę i informacje o błędach w logach technicznych, potrzebnych do obsługi połączeń i bezpieczeństwa.
- **Kontakt e-mail:** jeśli do nas napiszesz, przetwarzamy adres e-mail, treść wiadomości i informacje niezbędne do udzielenia odpowiedzi lub obsługi żądania.

Nazwy obserwowanych miejsc mogą ujawniać dane osobiste. Nie wpisuj w nich informacji, których nie chcesz przesłać przy włączaniu powiadomień dla tych miejsc.

## Dostawcy usług

**Oracle Cloud Infrastructure:** produkcyjne API działa na serwerze w regionie Frankfurt (Niemcy). Baza PostgreSQL/PostGIS działa na tym serwerze. Oracle zapewnia infrastrukturę hostingu; administrator obsługuje bazę i usługę. Kopie zapasowe mogą zawierać dane rejestracji i historię wysyłki. Aplikacja tego wydania łączy się z API `https://bezpieczna-polska-api.duckdns.org`, a nie ze starszym backendem Railway.

**Google Firebase Cloud Messaging:** Google przetwarza identyfikatory instalacji, tokeny i dane techniczne potrzebne do dostarczania powiadomień oraz przesłaną treść komunikatów. SDK może rozpocząć przetwarzanie przy inicjalizacji aplikacji, przed udzieleniem systemowego uprawnienia do wyświetlania powiadomień. Odmowa tego uprawnienia nie oznacza usunięcia identyfikatora Firebase. Firebase jest usługą globalną; dane mogą być przetwarzane poza Europejskim Obszarem Gospodarczym, także w USA. Google opisuje podstawy transferów, w tym EU–US Data Privacy Framework i warunki przetwarzania, w [informacjach o prywatności Firebase](https://firebase.google.com/support/privacy) i [warunkach przetwarzania danych](https://firebase.google.com/terms/data-processing-terms). Nie korzystamy w tym wydaniu z Firebase Analytics ani Crashlytics.

**Mapy i geokodowanie:** domyślny podkład pochodzi z OpenFreeMap. Dostawca map otrzymuje IP i żądania kafelków wskazujące oglądany obszar. Systemowe geokodowanie zależy od usługi dostępnej na urządzeniu, często usługi Google. Zewnętrzna aplikacja nawigacyjna otrzymuje punkt docelowy dopiero po jej otwarciu. Te usługi przetwarzają dane również na własnych zasadach.

**Google Play i strony zewnętrzne:** sklep obsługuje dystrybucję aplikacji na swoich zasadach. Otwarcie strony źródła, tej polityki lub innego linku przekazuje dane połączenia jej dostawcy. Polityka jest publikowana w publicznym repozytorium GitHub; jej odczyt podlega również [polityce prywatności GitHub](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

Nie sprzedajemy danych użytkowników. To wydanie nie zawiera SDK reklamowego, Sentry ani własnej integracji analitycznej. Nie wyklucza to przetwarzania danych technicznych przez Androida, Google Play i wymienionych dostawców.

## Podstawy prawne i wybór użytkownika

Przetwarzanie niezbędne do zapewnienia wybranych funkcji aplikacji, w tym obsługi zamówionych powiadomień i zapytań o okolicę, opiera się na art. 6 ust. 1 lit. b RODO (świadczenie usługi na żądanie użytkownika). Zapewnienie bezpieczeństwa, zapobieganie nadużyciom, diagnostyka wysyłki i obsługa zwykłej korespondencji opierają się na art. 6 ust. 1 lit. f RODO; naszym uzasadnionym interesem jest bezpieczne działanie usługi i rozwiązywanie zgłoszonych problemów. Realizacja obowiązków dotyczących praw osób opiera się na art. 6 ust. 1 lit. c RODO.

Podanie lokalizacji i włączenie powiadomień jest dobrowolne. Uprawnienie Androida jest kontrolą dostępu do funkcji urządzenia, a nie odrębną podstawą prawną całego przetwarzania. Odmowa nie blokuje przeglądania aplikacji; ogranicza funkcje wymagające lokalizacji lub powiadomień. Nie podejmujemy decyzji wywołujących skutki prawne na podstawie zautomatyzowanego profilowania.

## Przechowywanie i usuwanie

Ustawienia, cache i pakiety offline pozostają na telefonie do usunięcia właściwą funkcją aplikacji, wyczyszczenia jej danych w Androidzie lub odinstalowania. Poszczególne ustawienia można zmienić w aplikacji.

Aktywny token i preferencje są przechowywane na serwerze podczas rejestracji powiadomień. **Skuteczne wyrejestrowanie online** w ustawieniach powiadomień dezaktywuje instalację i usuwa z aktywnego rekordu token, język i preferencje, w tym obserwowane lokalizacje. Zachowane pozostają techniczny identyfikator, hash sekretu zarządzania, część metadanych i historia kolejki. Nie jest to całkowite usunięcie danych.

W obecnej wersji beta nie ma automatycznego terminu kasowania nieaktywnych rekordów instalacji ani historycznej kolejki. Pozostają do ręcznego usunięcia w ramach obsługi żądania lub porządkowania danych, z uwzględnieniem konieczności rozwiązywania problemów i ochrony przed nadużyciami. Logi i kopie zapasowe podlegają rotacji infrastruktury; nie deklarujemy jednego potwierdzonego maksymalnego terminu dla wszystkich kopii. Usunięcie danych z aktywnej bazy nie powoduje natychmiastowego usunięcia wcześniejszych kopii. W razie odtworzenia kopii żądanie usunięcia należy uwzględnić ponownie.

Samo odinstalowanie aplikacji, wyczyszczenie cache lub odmowa powiadomień w Androidzie nie usuwa rejestracji serwera. Bez internetu wyrejestrowanie może nie zakończyć się pomyślnie. W takim przypadku spróbuj ponownie po połączeniu lub skontaktuj się z administratorem.

Firebase przechowuje identyfikatory instalacji do zlecenia ich usunięcia odpowiednim API; Google podaje do 180 dni na usunięcie z systemów aktywnych i kopii po takim zleceniu. Wyrejestrowanie z naszego serwera nie zleca automatycznie usunięcia identyfikatora Firebase. Szczegóły i aktualne terminy dostawcy znajdują się w dokumentacji Firebase wskazanej powyżej.

Korespondencję przechowujemy przez czas obsługi sprawy, a następnie tylko w zakresie potrzebnym do udokumentowania jej rozstrzygnięcia i ochrony przed roszczeniami, do upływu właściwego okresu przedawnienia.

## Bezpieczeństwo

Produkcyjne połączenie aplikacji z API używa HTTPS. Tokeny push w bazie są szyfrowane. Sekret zarządzania instalacją jest przechowywany w bezpiecznym magazynie telefonu, a serwer przechowuje jego hash. Nie oznacza to szyfrowania end-to-end wszystkich danych ani treści przekazywanej do FCM.

## Twoje prawa

W zakresie wynikającym z RODO możesz żądać dostępu, kopii danych, sprostowania, usunięcia, ograniczenia przetwarzania i przenoszenia danych. Możesz wnieść sprzeciw wobec przetwarzania opartego na uzasadnionym interesie. Jeśli określone przetwarzanie opiera się na zgodzie, możesz ją wycofać bez wpływu na zgodność wcześniejszego przetwarzania.

Żądanie prześlij na **mati66628@gmail.com**. Opisz, jakiego zakresu danych dotyczy. Ponieważ nie wymagamy konta, może być konieczne uzgodnienie bezpiecznej weryfikacji powiązania z instalacją przed udostępnieniem lub usunięciem jej danych. **Nie wysyłaj e-mailem tokenu FCM, sekretu zarządzania instalacją ani kluczy.** Odpowiemy zasadniczo w ciągu miesiąca; przepisy pozwalają przedłużyć ten czas w uzasadnionych przypadkach po poinformowaniu Cię.

Możesz złożyć skargę do Prezesa Urzędu Ochrony Danych Osobowych: [uodo.gov.pl](https://uodo.gov.pl).

## Aktualizacje

Aktualizacje tej polityki publikujemy w pliku `docs/PRIVACY_POLICY.md` publicznego repozytorium [Bezpieczna Polska](https://github.com/mmaatteusz/bezpieczna-polska). Data na początku dokumentu wskazuje obowiązującą wersję. Istotne zmiany zakresu danych lub dostawców wymagają aktualizacji polityki i informacji Google Play o bezpieczeństwie danych.
