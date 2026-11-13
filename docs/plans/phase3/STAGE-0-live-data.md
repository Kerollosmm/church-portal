# المرحلة 0 — النهارده: تصرّف على البيانات الحية (Stage 0 — today: act on the live data)

**Objective:** put the live site in a clean state before any code changes. These are not code problems; they need
opening the panel and checking by hand. They rest on the trial of 12 November.

| | |
|---|---|
| **Items** | 1–5 of the unified list |
| **Owner** | Kerollos (items 1–3) · church office (items 4–5) |
| **Start gate** | the owner is signed in to https://maximos-domadios-church.web.app/admin |
| **End gate (G0)** | items 1–3 checked live and recorded; items 4–5 handed to the office with a named person |
| **Estimate (planning estimate)** | one working session for items 1–3; items 4–5 depend on the office |
| **Code changes** | none |

## المهام (Tasks)

| # | Task | Category | State | Current situation (report) |
|---|---|---|---|---|
| 1 | Delete the offensive trial notification from «سجل ما أُرسل», and confirm whether it reached people's devices | تحسينات أخرى | needs live check | Seen on 12 November as logged on 10 November. The code cannot tell whether it was deleted |
| 2 | Switch the stream off, or put the link in «اليوم والبث» | تحسينات أخرى | needs live check | The switch was on and the link empty. The panel still gives no automatic warning when this happens |
| 3 | Review the visible sample data (masses, priests and places still «غير مؤكد») | تحسينات أخرى | needs live check | 12 November: 47 masses, 4 priests and 4 places still unconfirmed. The public «بيانات غير مؤكدة» switch can show them all at once |
| 4 | Create the donations page for the new building (account / InstaPay / wallet) | الصفحات المخصصة | office task | Open in the memory bank. The ready template in the panel is not built yet (item 15) |
| 5 | Correct the church's English name in the church info | تحسينات أخرى | office task | Memory bank: the `nameEn` field needs correcting. **Owner decision, 13 November:** the live name "Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black" is canonical and stays; nothing to change |

Also from the report: donation account numbers and visitors' phone numbers are visible to every admin. That is
natural for the owner, but take care before adding editors. And prepare the seasons and notices for after 2027 if
that is still outstanding.

## الخطوات (Steps)

- [ ] **1.** Open the sent log, delete the offensive entry, then ask at least one subscribed person whether the
      notification arrived on their device. Record the answer in [STATUS.md](STATUS.md).
- [ ] **2.** Open «اليوم والبث». Either switch the stream off or paste the real link. Check the public home page.
- [ ] **3.** Go through masses, priests and places marked unconfirmed. For each: confirm with the church, or
      leave it marked. Decide whether the public «بيانات غير مؤكدة» switch stays on.
- [ ] **4.** Office: gather the real donation details and create the page with the existing page editor.
      Nothing is typed from memory or guessed.
- [x] **5.** No change: the owner keeps "Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black" as the canonical English name (13 November).
- [ ] Before adding any editor account, the owner reviews what an editor can see (donation accounts, visitors'
      phones).

## فحص من البيانات العامة (Check from the public data — 13 November 2026)

Read without signing in, from the publicly readable Firestore documents. It shows what a visitor's app receives;
it cannot see the admin-only sent log.

| # | What the public data shows | Verdict |
|---|---|---|
| 1 | Not visible: the sent log is in `settings/notifications`, readable by admins only | **owner must check in the panel** |
| 2 | `liveEnabled` is `false` and `liveUrl` is empty | stream is off — **looks resolved**; owner confirms |
| 3 | Still marked as sample data: 41 of 45 masses, 1 of 11 priests, 4 of 5 places (12 November: 47, 4, 4) | **open** — the owner decides item by item |
| 4 | Two visible pages exist: «التبرعات» (`/page/donations`) and «مبنى الكنيسة الجديد» (`/page/kiman-building-donations`) | pages exist — **office confirms the account details are the real ones** |
| 5 | `nameEn` is "Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black" | **resolved** — the owner confirmed this name as canonical (13 November) |

## قرار المالك (Owner statement — 13 November 2026)

The owner stated that items 1–5 are resolved, and G0 is passed on that statement. Items 1, 3 and 4 cannot be
checked without signing in, so they rest on the owner's word, not on the public-data check above.

## معايير القبول (Acceptance criteria)

- The offensive notification no longer appears in the log, and its delivery status is written down.
- The public site never shows a live-stream state with an empty link.
- The owner has decided, item by item, which sample data stays visible.
- Items 4 and 5 each have a named person in the office and a date.

## الاعتمادات (Dependencies)

None on code. Item 2's automatic warning is built later as part of item 23 («محتاج انتباهك»: stream on with no
link). Item 4 gets easier after item 15 but does not wait for it.
