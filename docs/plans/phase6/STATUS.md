# حالة التنفيذ (Phase 6 Status Tracker)

> Phase 6 implementation is **closed** on `main` as of 28 Nov 2026 (Africa/Cairo). This file is the in-repo close-out tracker. Remaining work is operational (24–48 h monitoring, optional web test, pubspec / public APK release) and is not a Phase 6 code packet.

---

## 1. المتطلبات المسبقة وإجراءات المالك والقرارات

- [x] **Prereq:** Phase 5 closed on `main` @ `1aa6ad6` (`#100` 5A, `#101` 5A-docs, `#102` 5B, `#103` 5C, `#104` 5D, `#105` 5E SKIP & STATUS closeout)
- [x] **Owner Action 1:** Off-box backup of the release keystore (`church-portal-release.jks` on Drive; passwords stored separately)
- [x] **Owner Action 2:** Cloudflare Worker crons confirmed and deployed. Live version at Stage 2 go: `8e1393f7` (owner ran `npx wrangler deploy`). Triggers: `*/15 * * * *` (sender), `7,22,37,52 * * * *` (queue drain), `3 2,8,14,20 * * *` (planner), `0 16 * * *` (readings)
- [x] **Owner Action 3:** Push launch secrets kept outside the repo. VAPID public key saved in `/admin → متقدم`. GitHub Actions secret `FIREBASE_SERVICE_ACCOUNT` added (required by `push-sender.yml`; distinct from `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL`)
- [x] **Q1 (`PR 6C`):** **DROPPED** — wording items not in codebase; revisit only if owner reports seeing them on live
- [x] **Q2 (`PR 6E`):** **Western digits with ص/م** (e.g. `08:00 ص – 09:30 ص`)
- [x] **Q3 (`PR 6E`):** **DROPPED** from `PR 6E`; re-check in Muse's `390 px` QA with a screenshot
- [x] **Q4 (`PR 6F`):** **APPROVED** — split into `PR 6F-1` (reads/prefetch) and `PR 6F-2` (banner/writes/emulator test)
- [x] **Q5 (`PR 6C`):** **APPROVED** — remove write-only `NotifyConfig.reminderSources`
- [x] **Q6 (`PR 6H`):** **APPROVED** — dedicated `test_*` topic via existing `push-sender.yml` `workflow_dispatch` (`topic_override`), no local CLI with the service account

---

## 2. حزم التنفيذ (merged)

| Packet | PR | Merge SHA | ADR | Notes |
|---|---|---|---|---|
| 6A web accessibility | [#107](https://github.com/Kerollosmm/church-portal/pull/107) | `040408b` | ADR-084 | |
| 6B push health | [#128](https://github.com/Kerollosmm/church-portal/pull/128) | `47810ce` | ADR-085 | |
| Web push health live stream | [#129](https://github.com/Kerollosmm/church-portal/pull/129) | `3ecce87` | ADR-086 | |
| 6C admin safety | [#130](https://github.com/Kerollosmm/church-portal/pull/130) | `cdcc6a3` | ADR-087 | |
| 6G cold load step 1 | [#131](https://github.com/Kerollosmm/church-portal/pull/131) | `5fff174` | ADR-088 | |
| 6D stream watchdog | [#132](https://github.com/Kerollosmm/church-portal/pull/132) | `91a6660` | ADR-089 | |
| Remove `daily_verses.json` preload | [#133](https://github.com/Kerollosmm/church-portal/pull/133) | `5e2dbdb` | — | |
| 6E quick public wins | [#134](https://github.com/Kerollosmm/church-portal/pull/134) | `5c6aa3c` | ADR-090 | |
| Post-6E share / readings redirect | [#173](https://github.com/Kerollosmm/church-portal/pull/173) | `dbf889b` | — | |
| 6F-1 offline reads | [#175](https://github.com/Kerollosmm/church-portal/pull/175) | `3661b18` | ADR-091 | |
| 6F-2 offline UX / writes | [#176](https://github.com/Kerollosmm/church-portal/pull/176) | `d7489f3` | ADR-092 | |
| 6H Stage 1 enabler (test-topic enrollment) | [#198](https://github.com/Kerollosmm/church-portal/pull/198) | `c75f878` | (code) | Hidden enrollment + isolated `topic_override` send path |
| 6H Stage 2 docs close-out | *(this PR)* | *(after merge)* | ADR-093 | PR-6H.md originally reserved ADR-092; 6F-2 already used it |

---

## 3. PR 6H — Narrow Push Launch then Broad Go

- [x] **P6H-0:** Pre-flight complete (6B/6G live, Worker crons + FCM secret + VAPID, keystore backed up)
- [x] **P6H-1 Android:** Passed 28 Nov 2026, 7:01 PM Africa/Cairo. Actions run [`46168247091`](https://github.com/Kerollosmm/church-portal/actions/runs/46168247091) on `main` @ `c75f878`, `topic_override: test_kerollos1`. Arrived once, clean Arabic, tap opened `/notifications`.
- [ ] **P6H-1 Web / PWA:** **Not run.**
- [x] **P6H-2 Owner go:** Explicit go 28 Nov 2026, 7:05 PM Africa/Cairo. The owner is turning on «تشغيل الإشعارات» in `/admin` himself.
- [ ] **P6H-2 24–48 h monitoring (pending):** `/admin → متقدم` drain & planner timestamps green, `capReached == false`; Sentry: no unexpected Worker or client push errors; Firebase Console (Spark): Firestore reads/writes and Hosting daily transfer within limits.

### Android test APK (follow-up, not a Phase 6 code packet)

- Local signed sideload **1.0.6** was built from `c75f878` for Stage 1 enrollment (arm64 versionCode `2007`, arm32 versionCode `1007`).
- `pubspec.yaml` is `1.0.6+7` with public `apk-v1.0.6` release (in-app update / `version.json`).

Ops reference: [`documentation/operations.md`](../../../documentation/operations.md) (Actions secret, enrollment, kill switch). Decision: [`ADR-093`](../../memory-bank/10-decisions-and-history.md).

---

## 4. فحص Muse المتبقي (read-only live QA, outside 6H launch)

- [ ] Mobile at `390 px` + screenshot check for empty image slots on «تذكار اليوم» / «القداس القادم»
- [ ] Issue [#174](https://github.com/Kerollosmm/church-portal/issues/174): Mobile (`390 px`) «باقي الأيام» day-tab chip clips at edge on `/mass-schedule`
