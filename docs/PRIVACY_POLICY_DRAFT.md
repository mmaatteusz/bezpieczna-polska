# Polityka prywatności aplikacji Bezpieczna Polska — projekt

**PROJEKT: nie publikować jako obowiązującej polityki przed uzupełnieniem
pól [DO UZUPEŁNIENIA] i potwierdzeniem konfiguracji produkcyjnej.**
Data opracowania: 4 października 2026 r. Data obowiązywania: [DO UZUPEŁNIENIA].

## Administrator i kontakt

Administratorem danych związanych z usługą Bezpieczna Polska jest
[DO UZUPEŁNIENIA: pełna nazwa/imiona i nazwisko, właściwe dane kontaktowe].
Kontakt w sprawach prywatności i realizacji praw:
[DO UZUPEŁNIENIA: publiczny adres e-mail].
Bezpieczna Polska jest niezależną aplikacją informacyjną. Nie wymaga konta
użytkownika; instalacja korzystająca z push posiada techniczny identyfikator.

## Jakie dane przetwarzamy i po co

- Na telefonie: wybrane województwo i miejscowość, współrzędne wskazanego
  punktu, obserwowane miejsca (nazwy, współrzędne, promienie), ustawienia
  wyglądu/map/powiadomień oraz cache i pobrane pakiety offline. Służą
  zapamiętaniu ustawień i wyświetlaniu informacji również bez sieci.
- GPS: aplikacja prosi system o dostęp do lokalizacji w związku z używaną
  funkcją. Można odmówić i wybrać miejscowość ręcznie. Backend otrzymuje
  współrzędne punktu przy zapytaniach o okolicę i najbliższe schronienia.
  Kod tych endpointów nie zapisuje historii przemieszczania; nie oznacza to,
  że wszystkie dane lokalizacyjne są przetwarzane wyłącznie na telefonie.
- Push: backend zapisuje identyfikator instalacji, platformę, token FCM,
  wersję aplikacji, ewentualny język, preferencje kategorii, województwo,
  daty rejestracji/aktywności i status urządzenia. Przy włączonej kategorii
  obserwowanych miejsc zapisuje także ich nazwy, współrzędne i promienie.
  Służy to doborowi i wysyłaniu powiadomień. Preferencje bez tej kategorii
  wysyłają pustą listę obserwowanych miejsc.
- Obsługa dostarczenia: kolejka backendu przechowuje identyfikator instalacji,
  identyfikator i rewizję komunikatu, kategorię, treść powiadomienia, daty,
  wynik prób i techniczne kody błędów. Przyjęcie wiadomości przez dostawcę
  nie dowodzi wyświetlenia na urządzeniu.
- Połączenia sieciowe: serwer, infrastruktura hostingu i dostawca map
  otrzymują adres IP oraz dane niezbędne do obsługi żądania. Produkcyjny kod
  API zapisuje trasę, status i czas odpowiedzi bez treści żądań. Osobne logi
  proxy/hostingu wymagają potwierdzenia w konfiguracji produkcyjnej.

Nazwy miejsc mogą ujawniać informacje osobiste. Nie wpisuj do nich informacji,
których nie chcesz przesłać przy włączeniu powiadomień dla tych miejsc.

## Dostawcy i przekazywanie danych

Android korzysta z Google Firebase Cloud Messaging. SDK Firebase może
przetwarzać identyfikatory instalacji i dane techniczne już przy inicjalizacji;
zgoda systemowa na wyświetlanie powiadomień nie stanowi dowodu, że SDK wcześniej
nie przetwarza danych. Zakres dla konkretnego wydania wymaga sprawdzenia
https://firebase.google.com/support/privacy i ustawień Firebase.

Domyślny podkład mapowy pochodzi z OpenFreeMap; wydanie może wskazywać inny
podkład. Żądania mapy ujawniają dostawcy IP oraz oglądany obszar.
Nawigacja otwiera zewnętrzną aplikację z punktem docelowym. Dostawca nawigacji
przetwarza dane na własnych zasadach. Otwarcie strony źródła lub polityki
prywatności również tworzy połączenie z wybraną stroną.

[DO UZUPEŁNIENIA: faktyczni dostawcy backendu, bazy, backupów i podkładu,
regiony przetwarzania, rola każdego podmiotu, umowy powierzenia, ewentualne
transfery poza EOG i właściwe mechanizmy prawne]. Nie zakładać, że migracja
Railway → Oracle zakończyła się ani że wszystkie usługi są w EOG.

## Podstawy przetwarzania i dobrowolność

[DO UZUPEŁNIENIA: odpowiednia podstawa prawna dla każdego celu — funkcje
usługi, fakultatywne powiadomienia/lokalizacje, bezpieczeństwo i diagnostyka;
przy uzasadnionym interesie wskazać konkretny interes].
Uprawnienie systemowe GPS/powiadomień i podstawa prawna przetwarzania są
odrębnymi sprawami. Odmowa GPS i powiadomień nie blokuje przeglądania aplikacji.

## Bezpieczeństwo, przechowywanie i usuwanie

Produkcyjny klient używa HTTPS. Backend szyfruje token push; sekret zarządzania
instalacją przechowuje na telefonie w secure storage, a serwer zapisuje jego
hash. Nie oznacza to szyfrowania end-to-end wszystkich danych.

Wyrejestrowanie w ustawieniach powiadomień, po skutecznym wykonaniu żądania
online, dezaktywuje instalację i usuwa aktywny token, język i preferencje
z lokalizacjami z rekordu urządzenia. Kod zachowuje techniczny identyfikator,
hash sekretu, część metadanych i historyczną kolejkę. Nie należy przedstawiać
tej operacji jako całkowitego usunięcia danych.

Sama odmowa powiadomień w Androidzie, odinstalowanie aplikacji lub czyszczenie
cache nie usuwają rejestracji backendu. Przy braku internetu zmiana ustawień
może nie zostać zastosowana na serwerze. Dane lokalne usuwa się przez właściwe
funkcje aplikacji lub wyczyszczenie danych aplikacji w Androidzie.

[DO UZUPEŁNIENIA: rzeczywiste terminy retencji aktywnych i nieaktywnych
instalacji, kolejki, logów, korespondencji i wszystkich kopii zapasowych;
procedura pełnego usunięcia lub anonimizacji i sposób obsługi żądania].
W sprawdzonym kodzie brak automatycznego terminu usuwania historycznych
rekordów push. Domyślne 14 dni dla lokalnych dumpów Oracle nie potwierdza
retencji wszystkich kopii ani faktycznej konfiguracji serwera.

## Prawa i skargi

W zakresie wynikającym z właściwych przepisów możesz żądać dostępu do danych,
ich sprostowania, usunięcia, ograniczenia przetwarzania i przenoszenia danych,
wnieść sprzeciw oraz wycofać zgodę, gdy przetwarzanie na niej bazuje.
Wycofanie zgody nie zmienia zgodności wcześniejszego przetwarzania.
Żądania kieruj na wskazany wyżej kontakt. Możesz złożyć skargę do Prezesa UODO
(https://uodo.gov.pl). [DO UZUPEŁNIENIA: bezpieczna weryfikacja instalacji
bez żądania od użytkownika tokenów FCM i sekretów w zwykłym e-mailu].

## Zmiany polityki i diagnostyka

W sprawdzonym wydaniu nie ma SDK reklamowego ani integracji Crashlytics/Sentry.
Nie oznacza to braku danych technicznych u hostingu, Firebase lub Google Play.
Przed dodaniem raportowania awarii należy ponownie opisać zakres danych,
dostawcę, konfigurację i retencję, zaktualizować Data safety i politykę.
Nowe wersje polityki będą publikowane pod [DO UZUPEŁNIENIA: publiczny URL HTML].
