# Operations & Deployment Runbook

This runbook covers operational procedures for the Church Portal: CI/CD deployment pipelines, secrets management, administrator provisioning, safe database seeding practices, Sentry error monitoring, and troubleshooting common operational issues.

For deep-dive memory bank references, see:
- [`docs/memory-bank/08-dev-workflow.md`](../../docs/memory-bank/08-dev-workflow.md) — Developer workflow, local gates, and seed rules.
- [`docs/memory-bank/05-firebase.md`](../../docs/memory-bank/05-firebase.md) — Hosting, App Check, and security configurations.

---

## 1. Automated CI/CD & Deployments

Deployments are fully automated through GitHub Actions. Manual production deployments from developer laptops are strictly prohibited under normal operations.

### Release Workflow
```mermaid
sequenceDiagram
    participant Dev as Developer / Agent
    participant PR as Pull Request
    participant CI as GitHub CI (ci.yml)
    participant Preview as Preview Channel (deploy.yml)
    participant Main as Branch: main
    participant Live as Live Production Deploy

    Dev->>PR: Push feature branch
    PR->>CI: Trigger test, analyze, seed diff, security rules emulator
    PR->>Preview: Deploy ephemeral preview channel (pr-NNN)
    CI-->>PR: Green checkmark
    Preview-->>PR: Comment with live preview URL (expires in 7 days)
    Dev->>Main: Squash-merge PR
    Main->>Live: Run deploy.yml (Rules + Indexes + Hosting + Sitemap)
    Live-->>Main: Site live on maximos-domadios-church.web.app
```

1. **Feature Branch:** Create a branch from `main` (`feat/…`, `fix/…`, `docs/…`). Direct pushes to `main` are blocked.
2. **Automated PR Gate (`ci.yml`):**
   - Flutter analyze (0 warnings/errors required).
   - Full test suite execution (`flutter test`).
   - Tool and web JS unit tests (`node --test web/*.test.mjs tool/*.test.mjs`).
   - Release web build verification with source maps.
   - Web bundle size & deferred isolation guard (`node tool/check_web_bundle.mjs build/web`): asserts `main.dart.js` `gzip -9 <= 1,396,031 B`, >= 6 part chunks, zero sourcemap leaks from 8 deferred modules, and OpenType font integrity.
   - Seed validation: verifies `assets/seed/seed.json` matches `tool/gen_seed.py` output byte-for-byte.
   - Firestore security rules testing in the local Firebase emulator (`tool/rules_test`).
3. **PR Preview Channel (`deploy.yml`):** Automatically builds and deploys an ephemeral preview channel at `https://maximos-domadios-church--pr-<number>-<hash>.web.app` (active for 7 days).
   - Runs informational non-blocking Lighthouse audit on the deployed preview URL and `/notifications` (`treosh/lighthouse-ci-action@v12`, 0 extra preview channels).
4. **Squash-Merge to `main`:** Squash-merging automatically triggers the production release in `deploy.yml`:
   - Deploys Firestore security rules and composite indexes.
   - Executes `tool/build_sitemap.sh` to generate `sitemap.xml` directly from Firestore (falls back to static sitemap if Firestore is unreachable).
   - Fingerprints icon fonts (`tool/fingerprint_icon_fonts.py`).
   - Deploys static build artifacts to Firebase Hosting target `app` (`maximos-domadios-church`) and target `legacy-redirect` (`asafra-church-portal`).

### Emergency Manual Deployment
In extreme emergencies where GitHub Actions is down, an authenticated administrator with Firebase CLI access can deploy manually:

```bash
# 1. Build web release with reCAPTCHA Enterprise site key
flutter build web --release --dart-define=RECAPTCHA_SITE_KEY=<YOUR_RECAPTCHA_KEY>

# 2. Build sitemap from Firestore (requires GOOGLE_APPLICATION_CREDENTIALS)
bash tool/build_sitemap.sh build/web/sitemap.xml

# 3. Fingerprint web icon fonts to prevent stale browser cache
python3 tool/fingerprint_icon_fonts.py build/web

# 4. Deploy to Firebase Hosting targets
npx firebase-tools deploy --only hosting:app,hosting:legacy-redirect --project asafra-church-portal
```

---

## 2. Secrets & Environment Variables

Configure these settings in **GitHub Repository → Settings → Secrets and variables → Actions**:

| Name | Type | Purpose & Scope |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL` | Secret | JSON private key for the Google Cloud service account (`github-deployer`). Required for deployment, PR previews, and sitemap generation. |
| `RECAPTCHA_SITE_KEY` | Variable | Public reCAPTCHA Enterprise site key ("church-portal-web") required for production builds to enable App Check and the AI Assistant. |
| `FIREBASE_WEB_API_KEY` | Secret / Variable | Optional. Extracted automatically from `lib/firebase_options.dart` if omitted. Used only for sending password reset emails to newly seeded admins. |
| `SENTRY_DSN` | Variable | Optional. A public fallback DSN is already embedded in `AppConfig.sentryDsn`. |
| `SENTRY_AUTH_TOKEN` | Secret | Optional. Reserved for future release source-map uploads. |

### Firebase API Key Security
The Firebase Web API key in `lib/firebase_options.dart` is a **public client identifier**, not a secret. It is embedded in compiled client JavaScript and transmitted openly in browser network headers. Data protection is enforced entirely by `firestore.rules`.
- Any GitHub Secret Scanning alert for this key is closed as a **`false_positive`**.
- To enforce defense-in-depth, API key restrictions in Google Cloud Console should restrict this key to: **Identity Toolkit API**, **Cloud Firestore API**, **App Check API**, and **Token Service API**.

---

## 3. Administrator Provisioning

The portal uses a hidden administrative dashboard at `/admin`. Admins authenticate using email and password.

### Recommended Admin Onboarding Procedure
1. Open **Firebase Console → Authentication → Users → Add User**.
2. Enter the administrator's email and a temporary strong password. Copy the generated **User UID**.
3. Sign in to **`/admin`** using an existing **Owner** account.
4. Navigate to **Admins («المشرفون»)** → click **Add Admin («إضافة مشرف»)**.
5. Paste the **UID**, enter the email, and choose the appropriate role:
   - **`editor` («محرر»):** Can edit all content, schedule details, custom sections, announcement banners, and view contact inbox messages.
   - **`owner` («مالك»):** Has all editor permissions plus the ability to add, modify, or remove administrator accounts.
6. The new admin logs in at `/admin` and changes their temporary password via the **Forgot Password? («نسيت كلمة المرور؟»)** flow.

> [!IMPORTANT]
> An administrator cannot change their own role or delete their own account. This structural rule ensures at least one owner account permanently exists. Maintain at least two distinct owner accounts for redundancy.

### Bootstrapping the Initial Owner
If no admin accounts exist yet (e.g. fresh database setup), create the initial owner document directly in Firestore:
- Collection: `admins`
- Document ID: `<AUTHENTICATED_USER_UID>`
- Document Body: `{"email": "admin@example.com", "role": "owner"}`

---

## 4. Safe Database Seeding

The seed content in `assets/seed/seed.json` is generated deterministically by `tool/gen_seed.py`. Seeding writes baseline documents to Firestore via `tool/seed_firestore.js` or the manual **Seed Firestore** GitHub Action.

### Seeding Modes & Safety Matrix

| Command / Flag | Behavior | Operational Risk | Recommended Use |
|---|---|---|---|
| `node seed_firestore.js --dry-run` | Simulates writes without modifying Firestore. | **Zero Risk** | Always run first before real writes. |
| `node seed_firestore.js --only <col>` | Writes only specified collections (e.g. `meetings,activities`). | **Low Risk** | Standard updates when adding new baseline categories. |
| `node seed_firestore.js --only settings --fill-missing` | Adds absent top-level fields to existing settings without overwriting. | **Low Risk** | Use after deploying new feature settings schemas. |
| Default (No flags) | Creates missing documents; skips existing ones. | **Medium Risk** | **Recreates deleted documents!** (e.g. removed clinics will reappear). |
| **`--force`** | **Overwrites all documents** and removes retired IDs. | **CRITICAL RISK** | **FORBIDDEN ON PRODUCTION.** Completely wipes non-developer admin edits. |

### Permanent Deletion of Seeded Items
Because default seeding recreates missing documents, deleting a seeded item in `/admin` is only temporary if someone runs the seeder later. To permanently retire a seeded item:
1. Open `tool/gen_seed.py`.
2. Remove the document definition from the generator.
3. Add its document ID to the `retired` dictionary under the appropriate collection key.
4. Run `python3 tool/gen_seed.py` (which validates `tool/known_seed_ids.json` and updates `tool/retired_seed_ids.json`).
5. Commit the generated files.

---

## 5. Sentry Observability & Monitoring

The portal integrates Sentry for privacy-first technical error reporting on Web and Android.

- **Dashboard:** <https://sentry.io> → Organization: `kerollos-0e` → Project: `church-portal`.
- **Environment Filtering:**
  - `production`: Live traffic on `maximos-domadios-church.web.app`.
  - `preview`: Automated PR preview channels.
  - `ci`: Build-time test runs.
- **Strict Privacy Scrubbing (PDPL Compliance):**
  - All form submission fields (names, phone numbers, emails, message text) are completely redacted before leaving the browser.
  - AI Assistant prompt questions and conversation history are never sent to Sentry.
  - IP address collection is disabled in client SDK configurations.
- **Diagnostic Verification:** Owners can trigger a benign test error in `/admin` → **Sections & Home Page** → **Error Reporting** → **Send test error («إرسال خطأ تجريبي»)**. Verify that `Test error from /admin (ignore)` appears in Sentry with tag `test: true`.

---

## 6. Troubleshooting Common Issues

| Symptom | Probable Cause | Corrective Action |
|---|---|---|
| **Footer displays "Showing bundled data saved with app" on live site** | The app is running on offline fallback because Firestore could not be read. | Check user internet connection, inspect Sentry for `content:<collection>` read errors, and verify that `firestore.rules` allows public reads. |
| **Admin save fails with `permission-denied`** | Document contains an unexpected key, exceeded length limit, or caller is not authenticated. | Check Firestore security rules key allow-list. Ensure all changed fields match the schema in `lib/domain/models.dart`. |
| **AI Assistant `/ask` is not visible** | Either the section toggle is disabled, or App Check failed to initialize. | Verify that `/admin` → **AI Assistant** has both switches enabled, and verify that `RECAPTCHA_SITE_KEY` is configured in CI/CD variables. |
| **AI Assistant says "Unable to get an answer"** | Gemini free-tier quota exhausted, invalid model specified, or App Check token rejected. | Check Sentry for `AssistantFailure` logs. In `/admin` → **AI Assistant**, clear the **Model** field to revert to the default `gemini-3.1-flash-lite`. |
| **Visitor reaches 3 questions limit** | Per-device daily question cap reached (resets at Cairo midnight). | The visitor must wait until midnight Africa/Cairo time, or an admin can raise the limit in `/admin` → **AI Assistant** → **Max questions per device per day**. |
| **Custom section or page displays "Section Unavailable"** | Document `visible` flag is `false` or the custom slug does not match. | Verify in `/admin` that the custom section/page has visibility set to true and that the URL slug matches the link. |
| **Icons appear blank or corrupted after a new deployment** | User browser cached an outdated web font version. | The CI pipeline's `tool/fingerprint_icon_fonts.py` step fingerprints font assets. Perform a hard refresh (Ctrl+F5) in the browser. |
| **CI build fails at "Check web bundle size & deferred chunk isolation"** | `main.dart.js` exceeded gzip ceiling (1,396,031 B) or a deferred module leaked into `main.dart.js.map`. | Ensure all 8 secondary modules are imported with `deferred as`. Run `node tool/check_web_bundle.mjs build/web` locally to inspect diagnostics. |
| **"Another admin modified this document" warning** | Concurrent edit detected via optimistic concurrency control (`updatedAt` check). | Click **Reload** to fetch the latest server version, then re-apply changes. |
| **Hero video does not play** | Visitor enabled reduced-motion or data-saver, or `heroMotion` is turned off. | This is expected accessibility behavior; the hero displays a static high-resolution poster or painting instead. (YouTube hero video was removed in PR #25). |
| **Top utility bar live badge does not appear on Home page** | Intentional default behavior (`liveBadgeHideOnHome: true`). | The Home page displays the prominent red live stream banner instead. Other sub-pages display the compact live badge. To display both on Home, toggle off **Hide live badge on Home when banner is showing** in `/admin` → **Today & Live Stream**. |
| **Android notifications delayed or missed** | OEM aggressive battery managers (MIUI/ColorOS/OneUI) killing background tasks. | Direct user to the in-app Battery Guidance screen (`/notifications/battery`) to whitelist the app from battery optimization and enable autostart. |

---

## 7. Android APK Packaging, Releases, and In-App Updates (ADR-058)

The native Android app is packaged as lightweight, split release APKs for maximum download efficiency and zero server-side push overhead (+0 Firestore reads/writes on Spark).

### Automated CI/CD Workflow (`.github/workflows/android.yml`)
- **Triggers:**
  - Automated release: Triggered whenever a tag matching `apk-v*` is pushed (e.g., `apk-v1.0.1`).
  - Prepared version: `pubspec.yaml` is `1.0.2+3` (version name `1.0.2`, build `3`). The higher build is what the in-app updater compares. Tag `apk-v1.0.2` is not pushed with the version bump; the public download stays the latest published `apk-v*` release (`apk-v1.0.1`) until that tag is pushed.
  - Manual testing: Triggered via `workflow_dispatch` on any branch.
  - Pull requests modifying Android assets or native code (`lib/**`, `android/**`, `pubspec.*`, `assets/**`, `.github/workflows/android.yml`).
- **Split APK Generation:** Produces two architecture-specific APK binaries:
  - `church-portal-arm64.apk` (`app-arm64-v8a-release.apk`) for modern 64-bit devices.
  - `church-portal-arm32.apk` (`app-armeabi-v7a-release.apk`) for older 32-bit devices.
- **Strict Size Budget Enforcement:** Build steps strictly assert binary limits prior to upload:
  - ARM64: `< 20 MB` (`20,971,520` bytes limit).
  - ARM32: `< 18 MB` (`18,874,368` bytes limit).
  Any size regression fails the CI pipeline before artifacts are released.
- **R8 Shrinking & Java 17 Desugaring:**
  - Uses full code minification (`isMinifyEnabled = true`) and resource stripping (`isShrinkResources = true`).
  - Implements core library desugaring via `com.android.tools:desugar_jdk_libs:2.1.5` on Java 17 target compatibility to support modern `java.time` APIs on older Android OS levels (minSdk 21).

### Keystore & Release Signing
- **Production Secrets:** Configured in GitHub Repository Secrets:
  - `ANDROID_KEYSTORE_BASE64`: Base64-encoded `release.jks` keystore.
  - `ANDROID_KEYSTORE_PASSWORD` / `KEYSTORE_PASSWORD`: Keystore password.
  - `ANDROID_KEY_ALIAS` / `KEY_ALIAS`: Key alias.
  - `ANDROID_KEY_PASSWORD` / `KEY_PASSWORD`: Key private password.
- **Automated Debug Fallback:** In pull requests, manual dispatch runs, or local builds without signing secrets, Gradle automatically falls back to the default Android debug signing config (`signingConfigs.debug`). Tagged release builds (`apk-v*`) strictly require the production secrets and fail immediately if they are missing to prevent distributing unsigned binaries.

### Release & Update Manifest (`version.json`)
- Post-build step executes `tool/make_apk_manifest.mjs` against generated APKs:
  - Computes byte sizes and cryptographic SHA-256 hashes.
  - Ingests version code, version name, minSupportedBuild, and release notes in Arabic and English.
  - Publishes `version.json` to Firebase Hosting under `/app/android/version.json`; every code deploy (`deploy.yml`) carries the live copy over so a release never disappears. `minSupportedBuild` comes from the `APK_MIN_SUPPORTED_BUILD` repository variable (default 1); `certSha256` from `apksigner`.
  - Configured with strict edge cache headers in `firebase.json` (`no-cache, no-store, must-revalidate`) ensuring devices immediately discover new releases.

### Katameros Daily Readings & Synaxarium Synchronization (ADR-063)
- Migrated from GitHub Actions (`synaxarium.yml`) into the Cloudflare Worker via Cron 4:
  - `0 16 * * *` (Cron 4): Runs daily at 18:00 Cairo time (16:00 UTC) corresponding to the liturgical day rollover at eve.
  - Invokes `syncDailyReadingsAndSynaxarium` (`tool/readings_syncer.js`) using pure Web-standard APIs (`fetch` and Web Crypto) with zero native Node.js dependencies.
  - Dual persistence: writes normalized Coptic lectionary readings and Synaxarium commemorations to Firestore REST path `readings/<YYYY-MM-DD>` authenticated via Google OAuth2 service account bearer token, and caches in Cloudflare KV under `reading:<YYYY-MM-DD>` with a 7-day TTL.
  - Idempotent: Skips duplicate API fetches and writes when data is already fresh in KV unless force-synced.

### In-App Update Verification & Installation Flow
1. When `installApkBuild` (admin) is greater than the app's build, the app fetches `/app/android/version.json`.
2. When `manifest.build > currentBuild`, a persistent update banner prompts the user.
3. Resumable downloading leverages HTTP `Range` headers to survive flaky network connections.
4. The downloaded APK's SHA-256 checksum is validated against the manifest.
5. The package signature is verified against the installed app's signing certificate using `PackageManager` before invoking the installer.
6. The app requests `REQUEST_INSTALL_PACKAGES` permission if not already granted, and launches the Android Package Installer session via secure `FileProvider` (`${applicationId}.updates`).
7. Forced updates are enforced if `currentBuild < minSupportedBuild`.

### Mobile Performance, Native Cream Splash & Single Back Arrow (ADR-062)
- **Native Launch Splash (`INV-SPLASH-01`):** Window launch background set to `#FBF3E4` (`@color/splash_cream`) across all Android versions (including Android 12+ Splash API via `values-v31` `windowSplashScreenBackground` and dark mode `values-night`), eliminating white or black flashes on cold start.
- **Hero Ambient Animation Gating (`INV-PERF-01`):** Continuous ambient canvas tickers (Ken Burns, haze drift, blurred light rays) are disabled on Android native APK (`heroAmbientLoopAllowed() == false`) to eliminate scroll frame drops and preserve battery, while hardware-decoded hero video remains active. Web retains full CSS DOM animations (ADR-037).
- **Navigation Chrome & Single Back Arrow (`INV-NAV-01`, `INV-NAV-02`):** Battery health guidance (`/notifications/battery`) renders standard `PageBody` + `PageHeader` chrome (no nested `Scaffold`), routing back to `/notifications`. Item detail pages (`ItemDetailPage`) omit the in-body back link on mobile viewports so that only `AppShell.leading` renders the single back arrow.

### OEM Battery Optimization Troubleshooting
- Aggressive OEM battery killers (Xiaomi MIUI/HyperOS, Oppo ColorOS, Realme UI, Huawei EMUI, Samsung OneUI, Vivo Funtouch) frequently suppress background tasks and delay exact alarms.
- Users reporting delayed or missed service reminders or daily readings notifications should be guided to the built-in diagnostic and guidance screen:
  - Route: `/notifications/battery` (accessible from `/notifications` preferences).
  - Diagnostic checks: Notification permission (`POST_NOTIFICATIONS`), Exact alarm permission (`SCHEDULE_EXACT_ALARM`), Battery optimization ignore status (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), and WorkManager periodic replenishment freshness.
  - Provides vendor-specific quick-launch intent actions for OEM autostart and background power management settings.

---

## 8. Scheduled Notification Sender & Cloudflare Worker (ADR-059, ADR-060, ADR-063)

The remote scheduled push delivery and readings synchronization infrastructure runs as a pure Web-API Cloudflare Worker with four scheduled crons defined in `wrangler.toml`:
1. `*/15 * * * *` (Cron 1): Scheduled notification sender, daily seasons alert, and due reminder dispatch using FCM boolean conditions (`'web_rem_...' in topics && !('app_...' in topics)`).
2. `7,22,37,52 * * * *` (Cron 2): Web push subscription queue drain (`push_queue`) via Google IID REST with subscriber health metrics written to `meta/push_topics`.
3. `3 2,8,14,20 * * *` (Cron 3): Web reminder planner compiling active liturgies, meetings, and special day events into `meta/push_plan`.
4. `0 16 * * *` (Cron 4): Daily Katameros lectionary & Synaxarium synchronization at 18:00 Cairo liturgical rollover (Firestore REST + KV).

### Cloudflare Worker Configuration & KV Caching
- **Cron Triggers:** 3 scheduled crons without a public `POST /trigger` endpoint to prevent unauthorized invocation or quota drain.
- **KV Token Cache (`PUSH_KV`):** Uses Cloudflare KV storage to cache Google OAuth2 access tokens (L2 cache after L1 memory), reducing token minting to ~1 per hour. Created via `npx wrangler kv namespace create PUSH_KV` and bound in `wrangler.toml`.
- **Worker Deployment:** Deployed via `npx wrangler deploy` (must be executed prior to merging into `dev` or `main`).
- **Worker Secrets (`wrangler secret put <KEY>`):**
  - `FIREBASE_PROJECT_ID`: Firebase project ID (`asafra-church-portal`).
  - `FIREBASE_CLIENT_EMAIL`: Service Account email with FCM and Firestore read/write permissions.
  - `FIREBASE_PRIVATE_KEY`: Service Account private key in PEM format (starting with `-----BEGIN PRIVATE KEY-----`).
  - `SENTRY_DSN`: Sentry DSN for error telemetry.
  - `SENTRY_CRON_MONITOR_ID`: Sentry Cron monitor ID for heartbeat health alerts.

### Spark Quota & Subrequest Budgets
- **Firestore Reads:** Uses REST `:batchGet` across all 3 crons (Cron 1 ~197 reads/day for settings + midnight seasons; Cron 2 up to 4 reads/run for meta and queue batch; Cron 3 ~5 reads 4x/day for planner) = ~500–600 reads/day total (well within the 50,000 daily Spark free tier).
- **Subrequest Limits:** Capped at 16 FCM topic dispatches and ≤ 25 total subrequests per run to strictly adhere to Cloudflare Worker free tier constraints.
- **Lease & Claims:** 120-second lease timeout with optimistic locking and exponential backoff on transient errors.

### Fallback GitHub Actions Workflow (`.github/workflows/push-sender.yml`)
- Provides manual dispatch (`workflow_dispatch`) fallback running `node tool/push_sender.js` using Node.js 22 LTS if Cloudflare Worker execution requires maintenance or debugging.
- Paired with `.github/workflows/keepalive.yml` running monthly to prevent automated GitHub Actions schedule deactivation.

---

## 9. Open Operational Tasks (Summary)

- Upload web source maps and Android symbols to Sentry (requires auth token).
- In Sentry: disable client IP collection and activate server-side scrubbers.
- Production signing & Play Integrity registration for Android APK.
- Server-side rate limiter for the AI Assistant.
- Configure required reviewers for GitHub `production` environment.
- Complete task tracker: [`docs/memory-bank/11-open-tasks.md`](../../docs/memory-bank/11-open-tasks.md).

