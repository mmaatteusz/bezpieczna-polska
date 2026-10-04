# Push: freshness and opening the selected alert

Base: main 6d24029, 0.1.0-alpha.66. Branch: fix/push-alert-lifecycle.

## Changed behavior

- Delivery deadlines are absolute from queue creation; retries cannot restart them.
- Upper bounds: air alerts 5 min, other critical 15 min, high 60 min, normal/informational 180 min, cyber/border 360 min. For active warnings validTo shortens the deadline. An end notification has its own 30 min window, because validTo is already in the past.
- Before every send, check the latest event revision, lifecycle, verification and expiration. Discard expired, superseded, missing or ineligible items. Legacy queued messages without a deadline are discarded rather than receiving an implicit four-week TTL.
- Provider acceptance is ACCEPTED/accepted_at, not proof of delivery. Migration 003 preserves historical acceptance timestamps and clears misleading delivered_at values.
- FCM sets remaining TTL and Android channel. Channels: Zagrożenia (high), Ostrzeżenia (default), Informacyjne (low). End and test notifications use Informacyjne. System/user channel preferences remain authoritative.
- Clicks resolve eventId via /v1/events/:id, including ended events and events outside the chosen province. Foreground Android intents carry separate identity and cold-start handling. FCM background taps use onMessageOpenedApp/getInitialMessage.
- An offline detail screen retains the requested identity, labels cached content as unconfirmed and retries on resume or every 15 s while foregrounded and offline. It does not substitute a different event.

## Validation completed

TypeScript build passed. Targeted push + production/migration tests: 28 passed, 1 PostGIS test skipped (no TEST_DATABASE_URL). Full backend: 237 passed, 10 skipped, 2 failures in shelter tests reproduced independently on unmodified main. Dart syntax parsed/formatted with the matching Flutter SDK's Dart formatter.

## Validation outstanding

Flutter dependency resolution was blocked by automatic review. Offline resolution cannot find flutter_lints and application dependencies in cache. Flutter analyzer, widget tests and Android/Kotlin build have NOT run. No physical Android device or production credentials were used; no real FCM E2E result is claimed. Not deployed, merged, pushed or released.

## Before merge

Run:

```sh
npm --prefix backend ci
npm --prefix backend run build
cd backend
node --import tsx --test test/push.test.ts test/production.test.ts
cd ../mobile
flutter pub get
flutter analyze
flutter test test/foreground_push_test.dart test/push_alert_page_test.dart test/push_notifications_test.dart
```

Apply migration 003 before starting the updated production backend. Production readiness refuses a schema without accepted_at. Validate PostgreSQL migration and dispatch with TEST_DATABASE_URL in an isolated test database. Upgrade backend and client together to activate all three channels in the client.

## Physical Android staging test (never inject test danger into production)

Use an isolated staging backend and a registered consenting test device. Create an actual-context synthetic event only in staging (the operational queue intentionally excludes TEST/EXERCISE/demo records). Keep the FCM service key and phone registration token secret.

1. App in background, internet on: create event A with a short future validTo. Confirm its PENDING row, provider ACCEPTED row, notification channel on phone and click opening A's exact title/id/current revision. Confirm acceptance alone is not recorded as phone delivery.
2. Repeat after terminating the app process normally, without Android force-stop. Click must open A from a cold start. Android force-stop intentionally suppresses messaging until the user starts the app.
3. Foreground: create different events A and B; click each notification and verify separate identities, then a correction of A. Confirm each severity channel in Android settings.
4. Phone offline before sending: restore network before TTL. Confirm the warning arrives and opens A. Cut network again before click: cached A must be labeled unconfirmed, or the screen must wait for A's content. Restore network: the same screen resolves A automatically.
5. Keep phone offline until after TTL/validTo; restore network. The expired warning must not arrive as a new alert. TTL governs undelivered messages; it does not remove an already displayed FCM system notification. Clicking an old visible notification must fetch the latest ended/expired status.
6. Pause staging dispatcher, queue active A, end/cancel or correct A, resume dispatcher. The old revision must be DISCARDED and only the eligible latest notification accepted.
7. Simulate provider outage or retry beyond deadline. Confirm DISCARDED, no restarted expiry window and no provider send after deadline.
8. Repeat with another province and Ukraine opt-in. Alert identity must not be limited to the current regional snapshot.

Record device model, Android version, APK SHA/version/signature, eventId/revision, publish/queue/accept/display/click times and connectivity transitions. Redact provider tokens and credentials from evidence. P0 remains open until these physical-device cases pass.
