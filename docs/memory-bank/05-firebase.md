# 05 — Firebase

> No secret values in this file. The service-account key lives only in the GitHub secret
> `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL`. The Firebase **web API key** in `lib/firebase_options.dart` (also used
> by `.github/workflows/seed.yml` to send a password-reset email) is a public client identifier, not a secret.

## Project

| | |
|---|---|
| Project id | **`asafra-church-portal`** (`.firebaserc` default, `FIREBASE_PROJECT_ID` in `deploy.yml`) |
| Project number / sender id | `724175543696` |
| Plan | **Spark** (no-cost) — per project setup, not visible in the repo. Business case recommends Blaze + $5 budget alert (see `11-open-tasks.md`). **Cloud Storage for Firebase is not available on Spark** (since Oct 2024 a default bucket needs Blaze; Spark projects cannot provision or access buckets — <https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024>), so uploaded images live in Firestore `media/` (ADR-017). |
| Firestore | Default database, location **`europe-west1`**, created in production mode (README) |
| Hosting | Site **`maximos-domadios-church`** → <https://maximos-domadios-church.web.app> (+ `.firebaseapp.com`) serves the app (target `app`); default site `asafra-church-portal` → `https://asafra-church-portal.web.app` only 301-redirects to the new domain (target `legacy-redirect`). Default site ids can't be renamed — ADR-018. |
| Web app id | `1:724175543696:web:8c75dcd193c3dc5106a715` |
| Android app id | `1:724175543696:android:93a4afeb7a9c7d9806a715`, package `com.asafrachurch.church_portal` |
| iOS | **Not registered**: `DefaultFirebaseOptions.ios` has `PLACEHOLDER_IOS_API_KEY` / `PLACEHOLDER_IOS_APP_ID`; bundle id `com.asafrachurch.churchPortal`. `currentPlatformOrNull` returns null → iOS runs on the seed. |

`lib/firebase_options.dart` notes: the Android options reuse the browser API key; if Android requests are rejected,
replace it with `current_key` from `google-services.json`. `flutterfire configure --project=asafra-church-portal`
regenerates the whole file (keep the `currentPlatformOrNull`/`isConfigured` helpers when you do).

## Authentication

- **Email/password** provider only; **admins only** (no public sign-up anywhere in the app).
- Accounts are created in Firebase console → Authentication → Users, or by the Seed workflow's `admin_email` input
  (`admin.auth().createUser`) which then emails a set-password (reset) link.
- Being signed in is not enough: admin rights = existence of `admins/{uid}` (see rules). Roles `owner`/`editor`.
- `/admin` has "Forgot password?" → `AdminRepository.sendPasswordReset` (answers the same whether the account exists).

## Firestore security rules (`firestore.rules`) — rule by rule

Helpers:
- `signedIn()` — `request.auth != null`.
- `isAdmin()` — signed in **and** `admins/{request.auth.uid}` exists.
- `isOwner()` — `isAdmin()` and that doc's `role == 'owner'` (missing role ≠ owner).
- Field validators: `optString(d,k,max)` (absent/null/string ≤ max), `str(d,k,max)` (cheaper: absent = '', null
  rejected — used on the big settings docs to stay under the 1000-expression budget), `reqString`, `optBool`,
  `optInt(lo,hi)`, `optNumber(lo,hi)`, `optTimestamp`, `optTime` (absent/null/''/`HH:mm`), `optList(max)`,
  `optIn(values)`.
- `stampOk(d)` — `updatedAt` absent, `== request.time`, or unchanged; `updatedBy` absent, equal to the caller's token
  email (or uid), or unchanged. Prevents forging edit history.
- `common(d)` — ≤ 60 keys, `visible`/`sample` bool, `order` int ±100000, `image` null/absent or `validImage`,
  `stampOk`. Putting the image check here (once) instead of in each `validX` keeps the expression count low; only
  collections whose allow-list contains `'image'` (alerts, seasons, activities, priests, milestones, saints) can
  actually store one.
- `validImage(i)` — map with keys ⊆ `source,url,mediaId,alt,w,h`; `source` ∈ url/inline/storage; inline →
  `mediaId` `^[A-Za-z0-9_-]{1,128}$`, otherwise `url` ≤ 500 matching `^https://[^/\s]+[.][^/\s]+([/?#][^\s]*)?$`;
  `alt` ≤ 300; `w`/`h` int 1–10000.
- `keysAllowed(allowed)` — **create**: all keys ∈ allowed; **update**: only *changed* keys ∈ allowed
  (`diff().affectedKeys()`), so legacy fields already in a doc never block an edit.

Match blocks:

| Path | read | create / update | delete |
|---|---|---|---|
| `/{col}/{docId}` for `alerts, seasons, liturgies, meetings, activities, clinics, facilities, priests, milestones, saints` | **public** | `isAdmin() && validContent(col, data)` → `common` + per-collection `validAlert/validSeason/validLiturgy/validMeeting/validActivity/validClinic/validFacility/validPriest/validMilestone/validSaint` (allow-list + types/sizes; see `04-data-model.md`) | `isAdmin()` |
| `/settings/{docId}` | **public** | `isAdmin()` and (`church` → `validChurch`, `features` → `validFeatures`); any other doc id denied | **never** |
| `/media/{mediaId}` | **get: public** (by id); **list: `isAdmin()` only** (PR 1, SEC-02) | `isAdmin() && validMedia(data)`: keys ⊆ `dataBase64, contentType, w, h, bytes, createdAt, createdBy, refs`; required `dataBase64` (4–950,000 chars), `contentType` ∈ jpeg/webp/png, `createdAt` (== `request.time`, or unchanged), `createdBy` (token email/uid, or unchanged); `bytes` ≤ 700,000; `w/h` 1–10000; `refs` list ≤ 20 | `isAdmin()` |
| `/admins/{uid}` | own doc, or any doc if `isOwner()` | `isOwner()` **and** `uid != caller` (cannot change yourself → an owner always remains); keys ⊆ `email, role, updatedAt, updatedBy`; email required ≤254; role ∈ owner/editor; `stampOk` (PR 1, SEC-03) | `isOwner() && uid != caller` |
| `/meta/contact_rate` | never | keys ⊆ `lastAt, lastMsgId`; `lastAt == request.time`; `lastMsgId` string 10–64 alphanumerics; `!exists(contact_messages/lastMsgId)` **and** `existsAfter(contact_messages/lastMsgId)` (so it is only writable in the same batch as a NEW message — SEC-01); and (new doc or `request.time > lastAt + 10 s`) | never |
| `/contact_messages/{id}` | `isAdmin()` | **create (public, no auth)**: `validContactMessage` **and** `getAfter(meta/contact_rate).lastAt == request.time` **and** `getAfter(meta/contact_rate).lastMsgId == id` (same batch). **update**: `isAdmin()`, only `status/updatedAt/updatedBy` change, status ∈ new/handled, `stampOk` | `isAdmin()` |

Anything not matched (e.g. a new collection) is **denied** by default — new collections need a rules change.

Notable details:
- `validSeason` requires `key` in the 6 season keys, `replacesRegular` optional bool (PR 1); `validLiturgy` requires
  the `start` key and `seasonKey` ∈ keys.
- Links (PR 1, SEC-04): `optHttpUrl` (`''` or `^[Hh][Tt][Tt][Pp][Ss]?://[^/ ]+[.][^/ ]+([/?#][^ ]*)?$` — scheme
  case-insensitive like the admin form) on `activities.link`,
  `meetings.facebookUrl/whatsappUrl` and `settings/church` `facebook/youtube/instagram/whatsappChannel`;
  `optUrlOrPath` (also an in-app path `/…`) on `alerts.link`. Rejects `javascript:`, `data:`, `//host`, etc.
  `mapsUrl`/`heroImageUrl` keep length-only checks.
- `validClinic`: `days` list ≤ 7 and ⊆ [1..7].
- `validPriest`: `rank` ∈ hegumen/priest, `status` ∈ serving/departed, dates ≤ 10 chars.
- `validFeatures`: exact key allow-list (also on update — `d.keys().hasOnly`), `sections` keys ⊆ the 16 section keys
  (incl. `media`)
  and values bool, `homeOrder`/`homeHidden` ⊆ the 7 block keys (≤ 7), `bannerLink` regex
  `^$|^/([^/ ][^ ]*)?$|^https?://[^/ ]+[.][^/ ]+([/?#][^ ]*)?$`, `theme` ∈ 5 presets.
- `validChurch`: phones/altars lists ≤ 20; `nameAr` required; `coordinatesApproximate` optional bool (PR 1).
- **Editors and owners have the same content/settings/inbox rights**; only `admins/*` management is owner-only.
- Tests: `tool/rules_test/rules.test.mjs` (Node test runner + `@firebase/rules-unit-testing` in the Firestore
  emulator, project `demo-church-portal`): public read/no write, non-admin denied, contact create + throttle,
  every seed doc valid, clinic create/hide/reorder/delete, unknown keys/bad types/bad times rejected, stamps,
  legacy fields, church coordinates, feature toggles shapes, inbox, owner/editor admin management, **optional
  images** (valid url/inline/null images, malformed maps, image on a collection without it, `media/` public read,
  admin-only writes, type/size/stamp checks, the 950,000-char cap), and PR 1's **SEC-01–SEC-04** (standalone
  `contact_rate` pings and mismatched `lastMsgId` rejected, 10 s throttle, `media` list admin-only, admin stamps,
  `Season.replacesRegular`, `coordinatesApproximate`, safe links incl. upper-case schemes, replaying an existing message, a 5 s resend). 32 tests.
- **Expression budget:** rules are limited to 1000 expressions per request (PR #3 hit it on `validChurch`). Keep new
  checks in shared helpers (`common`, `validImage`) and prefer `str()`/`get()` forms on big docs.

## Cloud Storage (not used — Spark)

- `storage.rules` in the repo root is a **draft, not deployed** (`firebase.json` has no `storage` entry): public read
  of `media/*`, admin-only writes (cross-service `firestore.exists(admins/uid)`), ≤ 700 KB, jpeg/webp/png
  (`^image/(jpeg|webp|png)([;].*)?$`, so parameterised headers like `image/jpeg; charset=utf-8` pass — PR 1).
- The app's `StorageMediaRepository` (`lib/data/media_repository.dart`) is a stub selected by
  `--dart-define=MEDIA_BACKEND=storage`; switch steps are in ADR-017 (`10-decisions-and-history.md`).
- Spark quota note: each inline image costs **one Firestore document read** per visitor session (cached in memory and
  by Firestore persistence), counted in the 50K reads/day. Keep images optional and few; the admin can switch them all
  off (section `media`).

## Indexes

`firestore.indexes.json`: `{"indexes": [], "fieldOverrides": []}` — no composite queries (see `04-data-model.md`).
Deployed with the rules on every push to `main`.

## Hosting (`firebase.json`, `.firebaserc`)

Two targets (array in `firebase.json`, mapped in `.firebaserc` → `targets.asafra-church-portal.hosting`):

| Target | Site | Serves |
|---|---|---|
| `app` | `maximos-domadios-church` (https://maximos-domadios-church.web.app) | The Flutter web app (settings below), live + PR previews |
| `legacy-redirect` | `asafra-church-portal` (old default site) | `redirects: [{regex: ^/(.*)$, destination: https://maximos-domadios-church.web.app/:1, type: 301}]` — every path keeps its path; public dir `hosting/legacy_redirect/` (meta-refresh fallback page only). `/__/*` reserved URLs still work there. |

Site `maximos-domadios-church` was created 1 Nov 2026 with `firebase hosting:sites:create` run by the deploy service
account from a throw-away workflow (SA has Hosting Admin). Auth **authorized domains** include
`maximos-domadios-church.web.app` and `.firebaseapp.com` (added in the console, 1 Nov 2026); both browser API keys
have no application (referrer) restriction, so no key change was needed. `authDomain` in `firebase_options.dart`
stays `asafra-church-portal.firebaseapp.com` (admin sign-in is email/password, no redirect/popup flow).

App target settings:

- `public: build/web` (output of `flutter build web --release`); ignores `firebase.json`, dotfiles, `node_modules`.
- `cleanUrls: true`, `trailingSlash: false`, **rewrite `**` → `/index.html`** (SPA + path URL strategy).
- Headers: `**` → `Cache-Control: no-cache` (Flutter bundles are not content-hashed, so HTML/JS must revalidate),
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options: SAMEORIGIN`,
  `Strict-Transport-Security: max-age=31536000; includeSubDomains`, `Permissions-Policy: camera=(), microphone=(),
  geolocation=()` (PR 1, SEC-05);
  images/fonts and `canvaskit/**` → `public, max-age=604800` (7 days).
- **Live** deploy: push to `main` → `deploy.yml` job `deploy-live` (`firebase deploy --only hosting:app,hosting:legacy-redirect`),
  environment `production` (URL the new domain).
- **Previews**: every same-repo PR → channel **`pr-<number>`** of the `app` target only (`--only app`), `--expires 7d`; the URL is posted/updated in one PR
  comment (marker `<!-- firebase-hosting-preview -->`). Previews are built **without** the reCAPTCHA key, so App Check
  is off there and the assistant is hidden; everything else works against the production Firestore (read-only for the
  public, real writes from the contact form and /admin!).
- Rollback: Firebase console → Hosting → release history → roll back.

## App Check (`lib/data/firebase_bootstrap.dart` `_activateAppCheck`)

| Build | Provider |
|---|---|
| Web release with key | `ReCaptchaV3Provider(AppConfig.recaptchaV3SiteKey)` |
| Web release without key (`PLACEHOLDER…` or empty) | **not activated** → `appCheckActive = false` → assistant hidden |
| Debug builds or `--dart-define=APPCHECK_DEBUG=true` | `WebDebugProvider` / `AndroidDebugProvider` / `AppleDebugProvider` (token from `APPCHECK_DEBUG_TOKEN` or SDK-generated and printed in console/logcat — register it under App Check → Manage debug tokens) |
| Android release | `AndroidPlayIntegrityProvider` (register the app's SHA-256 first) |
| iOS release | `AppleAppAttestWithDeviceCheckFallbackProvider` |

- **reCAPTCHA v3 site key**: `AppConfig.recaptchaV3SiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY',
  defaultValue: 'PLACEHOLDER_RECAPTCHA_V3_SITE_KEY')`. CI passes the **repository variable** `RECAPTCHA_SITE_KEY`
  (Settings → Variables, not a secret) only for push builds (`deploy.yml`). Status: **not set yet** → the live
  assistant is hidden. Register the key at google.com/recaptcha/admin (v3) for `maximos-domadios-church.web.app`,
  `maximos-domadios-church.firebaseapp.com`, `localhost`, then in Firebase console → App Check → Web app.
- App Check is **enforced for Firebase AI Logic** only. Do **not** enforce it on Firestore until the key is live, or
  all public reads fail.

## Firebase AI Logic — "Ask the church" assistant

- `firebase_ai`: `FirebaseAI.googleAI().generativeModel(model: AppConfig.geminiModel, systemInstruction:
  Content.system(instruction), generationConfig: GenerationConfig(temperature: 0.2, maxOutputTokens: 800))`
  (`lib/ui/pages/assistant_page.dart` `_session()`). **Gemini Developer API** backend.
- Model `gemini-2.5-flash` (override with `--dart-define=GEMINI_MODEL=...`; 2.5 Flash-Lite is closed to new projects).
- Visible only when `assistantVisibleProvider` is true: section `assistant` on **and** Firebase available **and**
  App Check active **and** `settings/church.assistantEnabled == true`.
- **Context building** (`lib/domain/assistant_context.dart` `buildAssistantInstruction`):
  1. Persona + rules: answer ONLY from the data; say you don't know and suggest calling; never invent times/names/
     phones; reply in the question's language; ≤ ~6 lines, bullets, times like 06:30 AM; all times Africa/Cairo with
     today's Cairo date; no medical/legal/spiritual-direction advice; collect no personal data; topics with no section
     are "not offered".
  2. Sections included **only if switched on** in `settings/features`: Contacts (contactInfo: address, directions,
     maps URL, phones; socials: WhatsApp, Facebook, YouTube, WhatsApp channel, Instagram); weekly liturgy schedule,
     special one-off services, Holy seasons (active seasons only, each labelled `[REPLACES regular schedule]` or
     `[ADDITIVE — regular morning masses continue]` from `replacesRegular`, plus `[ACTIVE NOW]`) (schedule); current
     announcements (alerts: `visibleAlerts`); clinics (active only, incl. WhatsApp); meetings (incl. notes);
     activities; public services (facilities); About the church (history: bishop + history summary, each language
     clipped to 700 chars);
     serving priests (priests) and departed priests with repose date (departedPriests); patron saints (saints).
     Every bilingual field goes through `_bi(ar, en)` → `"English (Arabic)"` or whichever one is filled, so
     Arabic-only admin entries never produce blank names/places (PR 1, BUG-04).
  3. Items with `sample: true` are prefixed **`[UNCONFIRMED]`** and the model is told to say they are provisional.
- Each user message is prefixed `[Current Cairo time: YYYY-MM-DD HH:mm (Weekday)]`; questions > 500 chars are ignored;
  45 s timeout.
- The chat is reused while the instruction string is identical; when content/date changes, a new session is started
  with the kept history (max 20 contents = 10 turns). If the set of enabled sections changes, history is cleared.
- Before the first question `_awaitContent()` waits (≤ 10 s) for settings, features, liturgies, seasons, clinics,
  meetings, activities, facilities, alerts, priests, saints.
- Kill switches (all platforms): section toggle `assistant` in /admin, `settings/church.assistantEnabled`, or App Check
  failing to activate. **Web release builds only:** a missing/placeholder reCAPTCHA key also hides it (App Check is
  skipped). Android/iOS release builds activate Play Integrity / App Attest without the key, so the assistant can
  still show there when the other conditions hold.
  Cost cap (Gemini quota) is a console task — not configured in code.

## Service account (CI/CD)

- GitHub secret **`FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL`** = full JSON key of a deploy service account
  (e.g. `github-deployer`). Used by `deploy.yml` (live, rules, preview) and `seed.yml` via the composite action
  `.github/actions/firebase-credentials`.
- Roles to grant (README §6): **Firebase Hosting Admin**, **Firebase Rules Admin**, **Cloud Datastore Index Admin**,
  **Service Account User**, **API Keys Viewer** (or simply *Firebase Admin*). The seed job additionally needs
  Firestore data write and Firebase Auth admin (for `--admin-email`) — *Firebase Admin* covers it.
- The account deliberately lacks `serviceusage.services.get`; the composite action **pre-seeds firebase-tools'
  `apiEnablementCache`** (`~/.config/configstore/firebase-tools.json`) for `firebasehosting`, `firestore`,
  `firebaserules`, `identitytoolkit` APIs instead of widening IAM (alternative: grant *Service Usage Consumer*).
- The action keeps only the **first JSON object** of the secret (stray characters after it produce a
  `::warning::Ignored N extra character(s)…` — re-save the secret cleanly; tracked in `11-open-tasks.md`), validates
  `type == service_account`, writes `$RUNNER_TEMP/sa.json` with mode 600, exports `GOOGLE_APPLICATION_CREDENTIALS`,
  never prints the key; every job deletes the file in an `if: always()` step.
- `.gitignore` blocks `*service-account*.json` / `*serviceAccount*.json`. Never commit keys.

## Local emulators

`firebase.json` has no `emulators` block; the rules tests start the Firestore emulator via
`firebase emulators:exec --only firestore --project demo-church-portal --config ../../firebase.json` (needs Java 11+;
CI uses Temurin 21). The devcontainer forwards 4000 (Emulator UI), 8085, 9099.
