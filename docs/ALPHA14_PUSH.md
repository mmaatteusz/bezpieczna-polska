# Alpha.14 — Push FCM/APNs

Alpha.14 dodaje powiadomienia jako **transport istniejących informacji**, a nie nowe źródło prawdy. Decyzje nadal wynikają z wersjonowanych `Event`/`Incident` i istniejących zasad statusu.

## Architektura

Przepływ:

`Event revision → reguły kwalifikacji → trwały push_outbox → dispatcher → FCM/APNs`

Parsery źródeł nie kontaktują się bezpośrednio z dostawcą push. Zapis rewizji, korelacja i utworzenie pozycji outbox odbywają się transakcyjnie. Ponowna synchronizacja identycznego Eventu nie tworzy kolejnego powiadomienia.

Outbox przechowuje stan `PENDING / SENDING / RETRY / DELIVERED / PERMANENT_FAILURE`, liczbę prób, termin kolejnej próby i bezpieczny kod błędu. Stare lease `SENDING` są odzyskiwane po restarcie. Po pięciu nieudanych próbach wpis staje się permanent failure.

## Rejestracja urządzeń

API:

- `POST /v1/push/devices` — pierwsza rejestracja,
- `PUT /v1/push/devices/:id` — aktualizacja i rotacja tokenu,
- `GET /v1/push/devices/:id` — stan rejestracji,
- `PUT /v1/push/devices/:id/preferences` — preferencje,
- `DELETE /v1/push/devices/:id` — unregister.

Każda instalacja ma losowy UUID v4 oraz osobny sekret zarządzający generowany lokalnie. Backend przechowuje wyłącznie hash sekretu. Token FCM/APNs jest szyfrowany AES-256-GCM; osobny hash tokenu służy tylko do wykrywania rotacji/reassignment. Unregister i permanent invalid-token usuwają użyteczny token z rekordu.

Payloady mają twarde limity, walidację Zod i per-route rate limiting. Tokeny i sekrety nie są zwracane przez API ani logowane.

## Reguły powiadomień

Powiadomienie może powstać dla nowego ważnego alertu, aktywacji, istotnej korekty, eskalacji albo zakończenia. Nie powstaje dla:

- samej zmiany `sourceHealth`,
- identycznego ponownego fetchu,
- `EXERCISE` / `TEST`,
- `REFUTED` lub danych niepotwierdzonych,
- pojedynczych publikacji Policji / PSP,
- stopni alarmowych administracyjnych,
- aktywnych danych NEPTUN.

Korelacja jest respektowana: jeżeli kilka Eventów tworzy jeden Incident, push jest emitowany wyłącznie dla jego aktualnego primary Eventu.

Kategorie użytkownika:

- krytyczne alerty Polski,
- obserwowane województwo,
- obserwowane lokalizacje,
- cyber,
- granice,
- alarmy Ukrainy.

Ukraina jest osobną kategorią i domyślnie jest wyłączona. Nie wpływa na Status Polski. NEPTUN w alpha.14 nie generuje push — również wtedy, gdy historyczny materiał przeszedł safety gate.

## Prywatność lokalizacji

Backend nie otrzymuje ciągłego GPS i nie zapisuje historii przemieszczania. Przy włączonej kategorii obserwowanych lokalizacji rejestracja przechowuje tylko aktualną listę zapisanych przez użytkownika punktów, promienie oraz opcjonalne województwo. Aktualizacja preferencji nadpisuje ten stan.

## Android / iOS

Flutter używa `firebase_messaging` do uzyskania tokenu FCM na Androidzie i tokenu APNs na iOS. iOS ma entitlement `aps-environment` zależny od konfiguracji Debug/Profile/Release.

Aplikacja **nie prosi o zgodę na starcie**. Użytkownik najpierw otwiera ekran Powiadomienia, czyta wyjaśnienie i dopiero po „Kontynuuj” uruchamiany jest systemowy permission request.

Ekran pokazuje jawnie:

- stan zgody systemowej,
- rejestrację tokenu,
- dostępność backendu,
- gotowość providera,
- przełączniki kategorii.

## Sekrety i konfiguracja

Sekrety providera są wyłącznie po stronie backendu:

- `PUSH_TOKEN_ENCRYPTION_KEY` — 32 bajty, hex64 lub base64,
- `FCM_SERVICE_ACCOUNT_JSON`,
- `APNS_KEY_ID`,
- `APNS_TEAM_ID`,
- `APNS_BUNDLE_ID`,
- `APNS_PRIVATE_KEY_P8`,
- opcjonalnie `APNS_ENV=sandbox`.

Nie trafiają do repo, APK ani logów. CI nie wymaga żadnego prawdziwego sekretu FCM/APNs i korzysta z fake providera.

Firebase client identifiers używane przez aplikację mobilną są osobną, publiczną konfiguracją klienta podawaną przez `--dart-define` (`FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_IOS_APP_ID`). Preview bez tych wartości nie inicjalizuje Firebase i pokazuje stan niekonfigurowany zamiast udawać działający push.

## CI

Workflow alpha.14 uruchamia pełne testy backendu z realnym PostGIS, regresje źródeł, testy Fluttera i push, a następnie buduje arm64-only preview APK. Nie wykonuje realnych wysyłek do FCM/APNs.
