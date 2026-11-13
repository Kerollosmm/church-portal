# حالة التنفيذ (Phase 3 status — tick as you go)

> Single checklist for the admin-panel simplification plan. Update it in the branch you are working on.
> Overview: [README.md](README.md) · how to build: [SMALL-MODEL-GUIDE.md](SMALL-MODEL-GUIDE.md).

## الوضع الحالي (Current state)

- **Baseline:** the report's last review, 13 November 2026 (Africa/Cairo), against the code after PR #70.
- **Counts:** 5 fixes on live data · 28 open tasks in the code · 8 done or removed · 1 deferred by decision.
- **Code:** no simplification code has changed since 12 November; the three stages have not started.
- **Next action:** Stage 0 — the owner opens the live panel (items 1–3) and hands items 4–5 to the office.

## قرارات مفتوحة للمالك (Open points for the owner — README §١٥)

- [ ] C4 — automatic sign-out value within 15–30 minutes (before Stage 1)
- [ ] C6 — do the screens moved under «الإعدادات (للمالك)» also become owner-only in the rules? (before Stage 2)
- [ ] C7 — approve the design note for item 28 (inside Stage 2)
- [ ] Item 32 — build the optional part or not (before Stage 3)

## المرحلة 0 — النهارده ([STAGE-0-live-data.md](STAGE-0-live-data.md))

- [ ] 1 — offensive trial notification deleted from «سجل ما أُرسل»; delivery to devices confirmed or ruled out
- [ ] 2 — stream switched off, or link set in «اليوم والبث»
- [ ] 3 — visible sample data reviewed (47 masses, 4 priests, 4 places unconfirmed on 12 November)
- [ ] 4 — donations page for the new building (office)
- [ ] 5 — `nameEn` corrected to "Church of the Saints Maximus and Domadius" (office)
- [ ] **G0**

## المرحلة 1 — الأمان والصفحات المخصصة ([STAGE-1-safety-and-custom-pages.md](STAGE-1-safety-and-custom-pages.md))

- [ ] 6 — confirmation before sending to everyone / «دلوقتي» (P1-06)
- [ ] 7 — «متابعة التعديل» prominent; browser Back, tab close and announcement «إلغاء» warn (P1-07)
- [ ] 8 — 10-second undo after delete; confirmations name the item (P1-08)
- [ ] 9 — state word next to every switch and on every row (P1-09)
- [ ] 10 — preview before «يحل محل قداسات اليوم المعتادة» (P1-10)
- [ ] 11 — fixed bottom save bar (P1-11)
- [ ] 12 — «نشط / موقوف» on every admin, optional end date (P1-12)
- [ ] 13 — automatic sign-out on the office device, «افتكرني» on a personal device (P1-13)
- [ ] 14 — automatic slug from the Arabic title (P1-14)
- [ ] 15 — ready «صفحة تبرعات» template (P1-15)
- [ ] 16 — one screen for sections and their items (P1-16)
- [ ] 17 — clearer empty state and hints (P1-17)
- [ ] Trial session after Stage 1 — date, servant, time taken, stops:
- [ ] **G1**

## المرحلة 2 — الوضوح وتقليل الخطوات ([STAGE-2-clarity-and-fewer-steps.md](STAGE-2-clarity-and-fewer-steps.md))

- [ ] 18 — menu from 25 entries to 7 groups (P2-18)
- [ ] 19 — title and help line on every screen (P2-19)
- [ ] 20 — serving and departed priests merged with a filter (P2-20)
- [ ] 21 — «متقدم» for the owner; no duplicated switches (P2-21)
- [ ] 22 — «افتح في الموقع» clearly external; trash away from the eye (P2-22)
- [ ] 23 — new home: «محتاج انتباهك» + the six task buttons (P2-23)
- [ ] 24 — phone and photo at the top of the form (P2-24)
- [ ] 25 — inbox opens on «محتاجة رد», with WhatsApp and «تمّت» (P2-25)
- [ ] 26 — picker for the priests' dates; labels without HH:mm (P2-26)
- [ ] 27 — error summary above the form (P2-27a) · «النسخة الإنجليزية» switch (P2-27b)
- [ ] 28 — sitemap updates when a page or section is added (P2-28)
- [ ] 29 — the assistant names visible sections and pages as topics (P2-29)
- [ ] Trial session after Stage 2 — date, servant, time taken, stops:
- [ ] **G2**

## المرحلة 3 — الباقي ([STAGE-3-remaining.md](STAGE-3-remaining.md))

- [ ] 30 — church info split; clearer coordinates; notice priority explained (P3-30)
- [ ] 31 — message types: clearer save, confirm before removal, «إعادة كجديدة» harder to hit (P3-31)
- [ ] 32 — one menu order for built-in and custom sections; item detail pages (optional) (P3-32)
- [ ] 33 — trial session with a real servant; panel at 320px; retest of the page jump / lost letters
- [ ] 34 — e-mail invitation of admins: **deferred** (no work)
- [ ] 35 — at least two owner accounts; photo of Abouna Domadius copied locally if it depends on YouTube (office)
- [ ] **G3 — ready for normal use (S1–S5)**

## اتعمل أو اتشال، فمش هنرجع ليه (Done or removed — not reopened)

| Item | State | Note |
|---|---|---|
| The word «العبادات» instead of «العيادات» in a help text | done | not in the current code; every text says «العيادات» |
| Year of a historical milestone without validation | done | now a number field with a minimum of 1 and a maximum of 2200 |
| Dates and time with a picker (ordinary fields) | partly done | ADR-049 / PR #42: 12-hour picker for `date`, `time` and `dateTime`; the rest is item 26 |
| Confirmation when applying a season, and the long-replacement warning | partly done | confirmation and warning in PR #48; the detailed preview for a single mass is item 10 |
| Delete confirmation in lists and when deleting a section | done | confirmed in the trial and the code; what remains is the name + undo (item 8) |
| Custom pages and sections in the sitemap | done | PR #30 / ADR-038, with each deploy; the immediate update is item 28 |
| Tour, «؟» button, full change log | removed from the plan | decision of 12 November; the help line and «آخر تعديل» are enough |
| Invitation of admins by e-mail | deferred | decision of 12 November; if needed: Cloudflare Worker; item 34 describes the current state |
