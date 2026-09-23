# Handoff — alpha.16 / przed alpha.16.1

Stan zgłoszony po merge PR #18 (23.09.2026); przed pracą potwierdź go zdalnie:

- `main`: `980668de4b3eefde14158f5f1e65543949e3cd0b`.
- Ostatni PR: #18 „Alpha.16: Production / Release Infrastructure”, merged/closed.
- Brak otwartych PR-ów; raportowane GREEN na `main`: production infrastructure/release gate, alpha.16 preview APK/offline regression, PSP shelter stage, RCB stage. Wyniki live source są doradcze, dostępność źródeł może się zmieniać.

## Działa w kodzie

- Flutter Android, wspólna baza kodu iOS, Status Polski/lokalny, źródła i STALE, historia i deduplikacja, RCB, RSO, częściowe WCZK, stopnie alarmowe, komunikaty PAA, CERT Polska, SG, publikacje Policji/PSP.
- Schronienia PSP, PostGIS, MapLibre, wyszukiwanie i najbliższe schronienie, pakiety offline regionu i lokalne obserwowane miejsca / „Wokół mnie” z GPS na żądanie.
- Ukraina (oddzielny moduł oficjalnych alarmów, wymaga klucza API), NEPTUN (wyłącznie historyczne ślady), kod push FCM/APNs z opt-in, outbox i kontraktami testowymi.
- Profile development/preview/production, migracje, PostGIS production requirement, health/readiness, metryki, backup/restore smoke, szablon Compose/Caddy/HTTPS, bramka wydania oraz pipeline podpisywania Androida. [Runbook](PRODUCTION_RUNBOOK.md).

## Ograniczenia i braki

- Brak publicznego hostingu/domeny, produkcyjnych sekretów i podpisanego przez właściciela wydania Androida; brak realnych wysyłek FCM/APNs i fizycznej walidacji iOS release. Zielony CI nie jest dowodem wdrożenia.
- PSP może zwrócić 403; brak sprawdzonego niezależnego oficjalnego fallbacku. WCZK nie pokrywa wszystkich województw niezależnymi adapterami. Pomiary PAA nie mają stabilnego zweryfikowanego kontraktu; CSIRT GOV pozostaje NOT_CONFIGURED.
- Panel administratora + MFA, pełny offline tileset oraz docelowy audyt i polityka prywatności pozostają otwarte.
- Brak danych ≠ bezpieczeństwo. STALE widoczne; Ukraina nie wpływa automatycznie na Status Polski; NEPTUN jest historyczny; stopnie alarmowe nie oznaczają automatycznie RED; publikacje służb nie podnoszą automatycznie statusu regionu.

## Następny etap

Alpha.16.1 porządkuje wersję, README/ROADMAP/SOURCES, workflowy i historyczny ZIP na branchu `stage/alpha16-1-cleanup`; PR musi przejść pełny CI i pozostać bez merge do polecenia użytkownika. Po alpha.16.1 rekomendowany jest jeden etap funkcjonalny z oficjalnym źródłem o sprawdzonym kontrakcie (np. ostrzeżenia IMGW), wybrany po weryfikacji dostępu i licencji. Nie pomijaj nierozwiązanych ograniczeń PSP/WCZK ani zasad semantyki statusu.
