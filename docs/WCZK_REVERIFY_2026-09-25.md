# WCZK / RSO — ponowna weryfikacja 16 województw

Data weryfikacji: **2026-09-25**

## Wniosek architektoniczny

Regionalny System Ostrzegania jest ogólnopolskim kanałem dystrybucji komunikatów
wprowadzanych przez Wojewódzkie Centra Zarządzania Kryzysowego. Dlatego aplikacja
nie modeluje 16 województw jako 16 niezależnych feedów ani 16 niezależnych
potwierdzeń.

Źródło nadrzędne dla automatycznej synchronizacji komunikatów WCZK:

- RSO: https://komunikaty.tvp.pl/
- publiczny XML używany przez backend:
  https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml

Oficjalne potwierdzenie modelu dystrybucji:
- MSWiA, RSO: https://www.gov.pl/web/mswia/regionalny-system-ostrzegania

Podkarpackie ma dodatkowo stabilną, oficjalną stronę ostrzeżeń, dla której
utrzymujemy bezpośredni parser HTML:
- https://rzeszow.uw.gov.pl/wczk/ostrzezenia

Ten parser jest **mirrorem tego samego wydawcy**, a nie drugim niezależnym
potwierdzeniem. Korelacja liczy rodzinę RSO/WCZK jako jedno źródło niezależne.

## Pokrycie

| Kod | Województwo | Automatyczne pokrycie | Dodatkowy adapter |
|---|---|---|---|
| 02 | Dolnośląskie | RSO / WCZK | brak |
| 04 | Kujawsko-pomorskie | RSO / WCZK | brak |
| 06 | Lubelskie | RSO / WCZK | brak |
| 08 | Lubuskie | RSO / WCZK | brak |
| 10 | Łódzkie | RSO / WCZK | brak |
| 12 | Małopolskie | RSO / WCZK | brak |
| 14 | Mazowieckie | RSO / WCZK | brak |
| 16 | Opolskie | RSO / WCZK | brak |
| 18 | Podkarpackie | RSO / WCZK | oficjalny mirror HTML |
| 20 | Podlaskie | RSO / WCZK | brak |
| 22 | Pomorskie | RSO / WCZK | brak |
| 24 | Śląskie | RSO / WCZK | brak |
| 26 | Świętokrzyskie | RSO / WCZK | brak |
| 28 | Warmińsko-mazurskie | RSO / WCZK | brak |
| 30 | Wielkopolskie | RSO / WCZK | brak |
| 32 | Zachodniopomorskie | RSO / WCZK | brak |

## Oficjalne strony administracji wojewódzkiej

Rejestr zachowuje adresy urzędów jako metadane wydawców:

- 02 https://www.gov.pl/web/dolnoslaski-uw
- 04 https://www.gov.pl/web/uw-kujawsko-pomorski
- 06 https://www.lublin.uw.gov.pl/
- 08 https://www.lubuskie.uw.gov.pl/
- 10 https://www.gov.pl/web/uw-lodzki
- 12 https://www.malopolska.uw.gov.pl/
- 14 https://www.gov.pl/web/uw-mazowiecki
- 16 https://www.gov.pl/web/uw-opolski
- 18 https://rzeszow.uw.gov.pl/wczk/ostrzezenia
- 20 https://www.gov.pl/web/uw-podlaski
- 22 https://www.gdansk.uw.gov.pl/
- 24 https://www.katowice.uw.gov.pl/usluga/ostrzezenia-i-raporty-wczk
- 26 https://www.gov.pl/web/uw-swietokrzyski/
- 28 https://www.gov.pl/web/uw-warminsko-mazurski
- 30 https://www.poznan.uw.gov.pl/
- 32 https://www.szczecin.uw.gov.pl/

## Zasady implementacji

1. Brak osobnego parsera wojewódzkiej strony nie oznacza braku pokrycia WCZK,
   jeżeli komunikaty regionu są dostarczane przez RSO.
2. Nie tworzymy duplikujących wpisów health dla 15 województw tylko po to,
   żeby pokazać je jako NOT_CONFIGURED.
3. Mirror wojewódzki i rekord RSO tego samego komunikatu mogą być skorelowane,
   ale nie zwiększają liczby niezależnych źródeł.
4. Direct scraper dodajemy tylko wtedy, gdy daje realną wartość ponad RSO i ma
   stabilny, weryfikowalny kontrakt. Nie zgadujemy endpointów.
5. Publiczny XML RSO pozostaje oznaczony jako lista publikacji, a nie jako
   kompletny kontrakt wszystkich aktywnych alarmów.
