# ROADMAP — Bezpieczna Polska

Aktualizacja: 22.09.2026 (alpha.15). To jest kanoniczna lista funkcji projektu. Status dotyczy aktualnego kodu w branchach etapowych, nie produkcyjnego wdrożenia.

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
| 23 | Pełniejsze pakiety offline mapy/regionu | ✅ |
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
| 37 | Push FCM/APNs | ✅ |
| 38 | „Jestem bezpieczny” przez systemowy Share Sheet | ✅ |
| 39 | Panel administratora + MFA | ❌ |
| 40 | Publiczny backend HTTPS + release APK | ❌ |

## Najbliższa kolejność

1. Publiczny backend, monitoring, backup, podpisane wydanie.
2. Panel administratora + MFA.

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

Następny etap: publiczny backend HTTPS, monitoring, backup i podpisane wydanie.