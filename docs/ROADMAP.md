# ROADMAP — Bezpieczna Polska

Aktualizacja: 21.09.2026. To jest kanoniczna lista funkcji projektu. Status dotyczy aktualnego kodu w branchach etapowych, nie produkcyjnego wdrożenia.

Legenda: ✅ gotowe w kodzie • 🟡 częściowo / wymaga domknięcia • ❌ do zrobienia • ⏳ później.

| # | Element | Stan |
|---:|---|:---:|
| 1 | Flutter Android | ✅ |
| 2 | Nawigacja Status / Mapa / RCB / Schronienie / Pomoc | ✅ |
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
| 23 | Pełniejsze pakiety offline mapy/regionu | 🟡 |
| 24 | Stabilny niezależny fallback PSP zamiast 403 | 🟡 |
| 25 | RSO XML | ✅ |
| 26 | WCZK per województwo | ❌ |
| 27 | Korelacja/deduplikacja RCB–RSO–WCZK | 🟡 |
| 28 | Timeline komunikatu w UI | ✅ |
| 29 | PAA | ❌ |
| 30 | CERT Polska / CSIRT GOV | ❌ |
| 31 | Straż Graniczna | ❌ |
| 32 | Istotne zdarzenia Policji / PSP | ❌ |
| 33 | Obserwowane lokalizacje | ❌ |
| 34 | „Co dzieje się wokół mnie?” | ❌ |
| 35 | Alarmy Ukrainy | ❌ |
| 36 | NEPTUN jako osobna warstwa OSINT | ❌ |
| 37 | Push FCM/APNs | ❌ |
| 38 | „Jestem bezpieczny” przez systemowy Share Sheet | ✅ |
| 39 | Panel administratora + MFA | ❌ |
| 40 | Publiczny backend HTTPS + release APK | ❌ |

## Najbliższa kolejność

1. WCZK i korelacja RCB–RSO–WCZK.
2. PAA.
3. CERT Polska / CSIRT GOV.
4. Straż Graniczna.
5. Obserwowane lokalizacje i „wokół mnie”.
6. Alarmy Ukrainy.
7. NEPTUN.
8. Push.
9. Pełniejsze offline.
10. Publiczny backend, monitoring, backup, podpisane wydanie.

## Zasady

Brak danych nie oznacza bezpieczeństwa. Źródła oficjalne, agregatory i OSINT zachowują odrębną tożsamość. Nie publikujemy fikcyjnych danych ani nie zgadujemy geometrii. Stopnie alarmowe są informacją o gotowości administracyjnej, nie automatycznym alarmem dla mieszkańca. Aktywne dane wojskowe i lokalizacje infrastruktury operacyjnej nie są celem aplikacji.
