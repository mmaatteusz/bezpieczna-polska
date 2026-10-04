# Wspólna integracja poprawek — 4.10.2026

Integracja łączy historie wszystkich 17 otwartych PR-ów ze wspólnym main.
Zachowuje nowszy kod tam, gdzie starsza propozycja nakładała się na późniejszą
implementację. Wersja aplikacji jest wspólna; osobne PR-y nie tworzą osobnych
kanałów instalacji. Development, preview i production nadal mają różne applicationId.

| PR | Wynik integracji |
| --- | --- |
| #75 | Odnośnik do zewnętrznej mapy RTGMS obok istniejącej warstwy GPSJAM; bez obietnicy pomiaru telefonu ani częstotliwości odświeżania. |
| #81 | Zachowany nowszy pojedynczy ekran BootstrapApp/BrandLoadingScreen z logiem i paskiem ładowania; brak powrotu do starej nakładki i sztucznego procentu. |
| #90 | Przyrostowy zapis SQLite, audit zmian/nowych/usuniętych rekordów i atomowy zapis health; PostGIS wykorzystuje nowszą wersję z #142. |
| #97 | Zachowany jeden niezależny worker Ukrainy, leasing i interwał 90 s z późniejszego main; usunięty konflikt tworzący drugi timer. |
| #100 | Zachowany aktualny parser nullable feedu live i rozróżnienie UNKNOWN/INFO jako informacji; nie cofnięto późniejszych ograniczeń kontraktu i znaczenia alarmu. |
| #106 | Zachowany bezpośredni odczyt /alerts i diagnostyka jego błędów; nie przywrócono zbędnego odpytywania historii wszystkich regionów. |
| #119 | Czytelne kolorowe znaczniki typów NEPTUN, bez sugerowania kierunku lotu. |
| #120 | Zachowana nowsza legenda zależna od widocznego kadru i warstw mapy. |
| #122 | Zachowane aktualne README i runbooki Oracle, backupu/restore oraz kontrolowanego przejścia klientów. |
| #123 | Ogólny klient production-runtime-smoke, jawne zmienne API i pierwszeństwo BUILD_SHA; zachowane osobne audyty health/identity, opt-in Oracle i adapter starszego Railway. |
| #128 | Manualne porównanie baseline/Oracle; zachowane kontrole SSH, backupu i odzyskiwania. |
| #139 | TTL push, ponowna walidacja aktualności kolejki, poprawne znaczenie przyjęcia przez dostawcę, kanały ważności i nawigacja do właściwego alertu. |
| #140 | Fixture dat schronień niezależne od dnia uruchomienia. |
| #141 | Lokalny zakres, maksymalnie trzy komunikaty, odświeżanie okolicy i świeżość istotnych źródeł na ekranie Start. |
| #142 | Deltas PostGIS, migracja worker_metrics, opcjonalne role procesów i metryki opóźnień/backupów/dysku. Domyślnie nadal combined. |
| #143 | Weryfikacja oryginalnych APK, podpisów i numerów oraz procedura migracji na ARM64. |
| #144 | Ekran prywatności, uczciwe ujawnienie współrzędnych push, projekt polityki, mapa Data safety i plan testów użytkowników. |

## Warunki wydania

Projekt polityki wymaga administratora, kontaktu, retencji i informacji o dostawcach.
Nie został zamieniony w finalną politykę. Produkcyjny build wymaga publicznej
polityki HTML HTTPS; preview może pokazywać skrót i informację o brakującym dokumencie.

Testy urządzeń push, TalkBack, odmów uprawnień, słabej sieci, długiej mapy i pełnej
migracji starego publicznego APK pozostają do wykonania według dokumentacji.
Scalenie nie jest dowodem wykonania tych prób ani wdrożenia nowej migracji bazy.

Integracja nie zmienia Repository Variables PRODUCTION_API_BASE_URL i PREVIEW_API_BASE_URL.
Nowe buildy korzystają z jawnie skonfigurowanych wartości; ręczny kanał Oracle pozostaje opt-in.
