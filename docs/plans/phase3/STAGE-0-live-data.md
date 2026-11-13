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
| 5 | Correct the church's English name in the church info | تحسينات أخرى | office task | Memory bank: the `nameEn` field needs correcting to "Church of the Saints Maximus and Domadius" |

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
- [ ] **5.** Office: change `nameEn` in church info to "Church of the Saints Maximus and Domadius".
- [ ] Before adding any editor account, the owner reviews what an editor can see (donation accounts, visitors'
      phones).

## معايير القبول (Acceptance criteria)

- The offensive notification no longer appears in the log, and its delivery status is written down.
- The public site never shows a live-stream state with an empty link.
- The owner has decided, item by item, which sample data stays visible.
- Items 4 and 5 each have a named person in the office and a date.

## الاعتمادات (Dependencies)

None on code. Item 2's automatic warning is built later as part of item 23 («محتاج انتباهك»: stream on with no
link). Item 4 gets easier after item 15 but does not wait for it.
