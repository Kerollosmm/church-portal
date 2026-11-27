# Integration Tests (Firestore Emulator)

`integration_test/offline_test.dart` verifies offline-first Firestore persistence (`disableNetwork()` / `enableNetwork()`), immediate cached reads, and offline contact form queuing (`hasPendingWrites`) + sync against the local Firestore emulator.

Because it requires a running Firestore emulator and a Flutter target device (Android emulator/device, or Windows/macOS desktop — `cloud_firestore` has no Linux desktop implementation), it is excluded from `flutter test` and is not run inside the headless unit-test CI job.

## Run Locally

Requires Java 21+ (for `firebase-tools ^15`), `firebase-admin` under `tool/` (for `tool/seed_firestore.js`), and `firebase-tools` (`npm ci --prefix tool/rules_test` or `npx firebase-tools`).

Install the Node dependencies once from the repository root:

```bash
npm install --prefix tool && npm ci --prefix tool/rules_test
```

### Windows / macOS desktop target

`firebase emulators:exec` automatically exports `FIRESTORE_EMULATOR_HOST`, so no POSIX `VAR=val` prefix is needed (works on Windows `cmd.exe`/PowerShell, macOS, and Linux):

```bash
npx firebase-tools emulators:exec --only firestore --project demo-church-portal --config firebase.json \
  "node tool/seed_firestore.js --project demo-church-portal && flutter test integration_test/offline_test.dart -d windows"   # or -d macos
```

(You can also invoke the locally installed CLI directly via `./tool/rules_test/node_modules/.bin/firebase`, or `tool\rules_test\node_modules\.bin\firebase` on Windows.)

### Android emulator target

On Android emulators, `localhost` on the device refers to the emulator itself; pass `10.0.2.2` to reach the host machine's Firestore emulator:

```bash
npx firebase-tools emulators:exec --only firestore --project demo-church-portal --config firebase.json \
  "node tool/seed_firestore.js --project demo-church-portal && flutter test integration_test/offline_test.dart -d emulator-5554 --dart-define=FIRESTORE_EMULATOR_HOST=10.0.2.2"
```
