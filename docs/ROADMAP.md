# ROADMAP — Bezpieczna Polska

Aktualizacja: 23.09.2026 (alpha.18, branch `stage/alpha18-source-completeness`, PR #22). To jest stan bieżącego brancha przed merge; `main` pozostaje na alpha.17.1 do czasu pełnego CI GREEN.

Legenda: ✅ gotowe w kodzie • 🟡 częściowo / wymaga domknięcia • ❌ do zrobienia • ⏳ później.

| # | Element | Stan |
|---:|---|:---:|
| 1 | Flutter Android | ✅ |
| 2 | Nawigacja Status / Mapa / Alerty / Schronienie / Pomoc | ✅ |
| 3 | Backend TypeScript | ✅ |
| 4 | PostgreSQL | ✅ |
| 5 | PostGIS | ✅ |
| 6 | Wspólny Event | ✅ |
| 7 | Historia rewizji | ✅ |
| 8 | sourceHealth | ✅ |
| 9 | Status Polski | ✅ |
| 10 | Status regionu | ✅ |
| 11 | Wyjaśnienie „Dlaczego taki status?” | ✅ |
| 12 | RCB | ✅ |
| 13 | Cache RCB/offline snapshot | ✅ |
| 14 | Stopnie alarmowe RP | ✅ |
| 15 | Równoległe stopnie PHYSICAL/CRP | ✅ |
| 16 | Stopnie alarmowe nie wymuszają RED | ✅ |
| 17 | Oficjalny katalog schronień PSP | ✅ |
| 18 | Wyszukiwanie schronień | ✅ |
| 19 | GeoJSON schronień | ✅ |
| 20 | MapLibre | ✅ |
| 21 | Bbox/PostGIS dla mapy | ✅ |
| 22 | Clustering schronień | ✅ |
| 23 | Pełniejsze pakiety offline danych regionu (bez basemapu) | ✅ |
| 24 | Stabilny niezależny fallback PSP zamiast 403 | 🟡 |
| 25 | RSO XML | ✅ |
| 26 | WCZK per województwo | 🟡 |
| 27 | Korelacja/deduplikacja RCB–RSO–WCZK | ✅ |
| 28 | Timeline komunikatu w UI | ✅ |
| 29 | PAA | 🟡 |
| 30 | CERT Polska / CSIRT GOV | 🟡 |
| 31 | Straż Graniczna | ✅ |
| 32 | Istotne zdarzenia Policji / PSP | ✅ |
| 33 | Obserwowane lokalizacje | ✅ |
| 34 | „Co dzieje się wokół mnie?” | ✅ |
| 35 | Alarmy Ukrainy | ✅ |
| 36 | NEPTUN jako osobna warstwa OSINT | ✅ |
| 37 | Push FCM/APNs: kod, opt-in i outbox | ✅ |
| 38 | „Jestem bezpieczny” przez systemowy Share Sheet | ✅ |
| 39 | Panel administratora + MFA | ❌ |
| 40 | Publiczny backend HTTPS + release APK | ❌ |
| 41 | Konfiguracje development / preview / production | ✅ |
| 42 | Migracje produkcyjne, idempotencja i wymaganie PostGIS | ✅ |
| 43 | `/health`, `/ready`, sourceHealth i STALE | ✅ |
| 44 | Skrypt backup, restore i smoke test na oddzielnej bazie | ✅ |
| 45 | Monitoring/metrics i logi aplikacji | ✅ |
| 46 | Szablon Compose z Caddy gotowy do HTTPS | ✅ |
| 47 | Release gate z kontrolą backendu i wersji | ✅ |
| 48 | Pipeline podpisanego Android AAB/APK | ✅ |
| 49 | Prawdziwa domena i publiczny hosting | ❌ |
| 50 | Realne sekrety produkcyjne i klucz właściciela do podpisu | ❌ |
| 51 | Wygenerowany właścicielskim kluczem podpisany release | ❌ |
| 52 | Produkcyjne wysyłki FCM/APNs | ❌ |
| 53 | Fizyczna walidacja iOS release na sprzęcie | ❌ |
| 54 | IMGW-PIB: oficjalne ostrzeżenia meteorologiczne i hydrologiczne | ✅ |
| 55 | Audyt kompletności źródeł i jawne PARTIAL / NOT_CONFIGURED | ✅ |
| 56 | Wersjonowane migracje DB + lease workerów ingest/push | ✅ |
| 57 | Nearest shelter: współrzędne w POST body zamiast URL | ✅ |
| 58 | File-backed pakiety offline + SHA-256 + legacy LKG | ✅ |
| 59 | Pełny podkład mapowy offline | ❌ |
| 60 | Release/preview CI bez twardych zależności od numeru alpha | ✅ |

## Najbliższa kolejność

1. Domknąć alpha.18: przywrócić działanie GitHub-hosted Actions, uzyskać pełny wymagany CI GREEN i dopiero wtedy merge PR #22.
2. Rozwijać kolejne pełne adaptery WCZK / PAA / CSIRT GOV wyłącznie po potwierdzeniu stabilnego oficjalnego kontraktu; nie podnosić kompletności źródeł częściowych.
3. Pełny basemap offline wdrażać dopiero z kontrolowanym źródłem danych/kafli, limitami rozmiaru i niezależnym lifecycle od pakietu bezpieczeństwa.
4. Panel administratora + MFA przed produkcyjnym użyciem endpointów administracyjnych.

Uwagi do częściowych etapów: WCZK ma jeden niezależny adapter oraz integrację RSO dla pozostałych publikacji; PAA ma komunikaty, ale pomiary pozostają zablokowane przez brak zweryfikowanego publicznego kontraktu; CERT Polska działa z oficjalnego RSS, publiczna lista RSS CSIRT GOV jest obecnie pusta, a Straż Graniczna korzysta z oficjalnych Aktualności z konserwatywnym filtrem komunikatów operacyjnych (publiczna lista RSS KGSG jest pusta). Alpha.11 dodaje lokalne obserwowane miejsca oraz zapytania „Wokół mnie”: odległość jest liczona tylko dla Eventów z geometrią, a jawny zakres krajowy/wojewódzki jest prezentowany osobno bez udawania bliskości.

## Zasady

Brak danych nie oznacza bezpieczeństwa. Źródła oficjalne, agregatory i OSINT zachowują odrębną tożsamość. Nie publikujemy fikcyjnych danych ani nie zgadujemy geometrii. Stopnie alarmowe są informacją o gotowości administracyjnej, nie automatycznym alarmem dla mieszkańca. Aktywne dane wojskowe i lokalizacje infrastruktury operacyjnej nie są celem aplikacji.


## Alpha.12 — Ukraina

Oficjalny adapter UkraineAlarm v3, cykle i korekty, niezależność statusu PL, PostGIS i bounded offline snapshot, moduł Ukraina + administracyjna warstwa MapLibre. Live wymaga klucza. Szczegóły: [ALPHA12_UKRAINE.md](ALPHA12_UKRAINE.md).

## Alpha.13 — NEPTUN

Osobny historyczny moduł OSINT: zakończone ślady, obserwacje, timeline, provenance, semantyczna weryfikacja, korekty i zgrubna mapa. Publiczne API wymusza co najmniej 24 h opóźnienia oraz minimum 10 km deklarowanej dokładności geometrii. Brak automatycznego feedu — nie publikujemy aktywnych dokładnych pozycji. Szczegóły: [ALPHA13_NEPTUN.md](ALPHA13_NEPTUN.md).

## Alpha.14 — Push FCM/APNs

Szyfrowana rejestracja urządzeń, rotacja tokenów, preferencje, trwały outbox z deduplikacją/retry/permanent failure, adaptery FCM/APNs oraz jawny opt-in UX w Flutterze. Push nie zmienia Statusu Polski; Ukraina pozostaje osobną kategorią, a NEPTUN nie generuje operacyjnych powiadomień. Szczegóły: [ALPHA14_PUSH.md](ALPHA14_PUSH.md).

## Alpha.15 — Offline regionu

Atomowe pakiety województwa z manifestem/integrity, pełnym lokalnym katalogiem schronień, lokalnym nearest/search/Wokół mnie oraz overlayami mapy. Offline jest zawsze jawnie LAST KNOWN GOOD, bez udawania aktualności i bez fałszywego offline tilesetu. Szczegóły: [ALPHA15_OFFLINE.md](ALPHA15_OFFLINE.md).

## Alpha.16 — infrastruktura wydania

W kodzie: konfiguracje trzech środowisk, produkcyjne migracje i wymaganie PostGIS, readiness/health, backup i restore smoke test, metryki, szablon Caddy/HTTPS, release gate oraz pipeline Android signing. Weryfikacja CI nie zastępuje wdrożenia. Nadal brak hostingu i domeny, realnych sekretów, właścicielskiego podpisanego artefaktu, produkcyjnego FCM/APNs i fizycznej walidacji wydania iOS. Szczegóły: [PRODUCTION_RUNBOOK.md](PRODUCTION_RUNBOOK.md).


## Alpha.17 — IMGW-PIB

Dwa oficjalne endpointy ostrzeżeń są włączone jako niezależne źródła. Parser waliduje TERYT/województwa, stopnie i okresy ważności, nie tworzy geometrii z tekstu i obsługuje wyłącznie dokładnie rozpoznany wariant pustej listy IMGW. Szczegóły: [ALPHA17_IMGW.md](ALPHA17_IMGW.md).


## Alpha.18 — source completeness i runtime hardening

Branch alpha.18 dodaje audyt kompletności źródeł, jawne etykiety źródeł częściowych/niepodłączonych, wersjonowane migracje, DB-backed lease dla workerów, POST dla precyzyjnych współrzędnych nearest shelter, file-backed storage pakietów offline z SHA-256 oraz wersjo-niezależne release gate. Nie dodaje pełnego basemapu offline i nie zmienia źródła częściowego w „pełne” bez zweryfikowanego kontraktu. Szczegóły: [ALPHA18_SOURCE_AUDIT.md](ALPHA18_SOURCE_AUDIT.md).
