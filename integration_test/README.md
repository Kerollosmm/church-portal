# Integration Tests (Firestore Emulator)

`integration_test/offline_test.dart` verifies offline-first Firestore persistence (`disableNetwork()` / `enableNetwork()`), immediate cached reads, and offline contact form queuing (`hasPendingWrites`) + sync against the local Firestore emulator.

Because it requires a running Firestore emulator and a Flutter target device (Linux desktop, Chrome, or Android emulator), it is excluded from `flutter test` and is not run inside the headless unit-test CI job.

## Run Locally

Requires Java 11+ and `firebase-tools` (`npm ci` in `tool/rules_test` or `npx firebase-tools`).

### Linux / Desktop target

```bash
cd tool/rules_test && npm ci && cd ../..
npx firebase emulators:exec --only firestore --project demo-church-portal --config firebase.json \
  "FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/seed_firestore.js && \
   flutter test integration_test/offline_test.dart -d linux"
```

### Android emulator target

On Android emulators, `localhost` on the device refers to the emulator itself; pass `10.0.2.2` to reach the host machine's Firestore emulator:

```bash
npx firebase emulators:exec --only firestore --project demo-church-portal --config firebase.json \
  "FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/seed_firestore.js && \
   flutter test integration_test/offline_test.dart -d emulator-5554 \
     --dart-define=FIRESTORE_EMULATOR_HOST=10.0.2.2"
```
