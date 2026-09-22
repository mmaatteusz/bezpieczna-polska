# Alpha.11 — obserwowane lokalizacje + „Wokół mnie”

## Cel
Dodać lokalny, prywatnościowy kontekst miejsca bez budowania historii ruchu użytkownika.

## Zasady
- GPS wyłącznie po świadomej akcji użytkownika.
- Brak background tracking, geofencingu systemowego i historii pozycji.
- Jednorazowa pozycja „Wokół mnie” pozostaje tylko w pamięci procesu.
- Obserwowane lokalizacje są zapisywane wyłącznie lokalnie na urządzeniu; backend dostaje współrzędne dopiero przy ręcznym sprawdzeniu konkretnego miejsca.
- Odległość do Eventu jest liczona tylko wtedy, gdy Event ma wiarygodną geometrię ze źródła.
- Brak geometrii nie oznacza braku zdarzeń w pobliżu.
- Kontekst regionalny może być pokazany osobno tylko dla jawnego zakresu NATIONAL/PROVINCE; nie udajemy odległości.
- Nearest shelter korzysta z istniejącego oficjalnego katalogu PSP i zachowuje jego sourceHealth/STALE.

## Plan API
`GET /v1/around?lat=&lon=&radiusKm=&regionId=`

Odpowiedź rozdziela:
- `nearbyEvents` — tylko zdarzenia z geometrią i obliczoną odległością,
- `regionalEvents` — jawne komunikaty krajowe/wojewódzkie bez twierdzenia, że są blisko,
- `nearestShelters`,
- jawny opis częściowego pokrycia przestrzennego.

## UI
Osobna sekcja „Wokół mnie”:
- jednorazowe sprawdzenie GPS,
- lista obserwowanych miejsc,
- dodawanie miejsca z bieżącej pozycji lub ręcznych współrzędnych,
- etykieta np. Dom / Praca / Rodzina / Szkoła,
- promień 1–100 km,
- opcjonalne województwo do kontekstu regionalnego,
- usuwanie zapisanej lokalizacji.

## Poza zakresem alpha.11
- ciągłe śledzenie,
- background geofencing,
- historia ruchu,
- push,
- geokodowanie tekstu do punktu,
- automatyczne reverse geocoding,
- Ukraina / NEPTUN.
