# المرحلة الثالثة — تبسيط لوحة الإدارة (Phase 3 — admin panel simplification)

> **Source:** the report «خطة تبسيط لوحة الإدارة — church-portal – كنيسة القديسين مكسيموس ودوماديوس», exported
> from the unified plan page, last review 13 November 2026 (Cairo time, Africa/Cairo).
> Plan page: https://cursor.com/canvas/store-fe4456b6-bf15-4ef6-8eea-c57d9afa7657/285d2f86-36cd-41e7-a866-c60ba74fc660
>
> Everything below restates that report. Where this plan adds something the report does not state (time
> estimates, proposed identifier names, PR grouping), it is marked **(planning estimate)** or **(proposed)**.

## ١. الهدف (Goal)

«أي خادم في الكنيسة، حتى لو ما بناش اللوحة، يقدر يعمل أي تعديل يومي في 3 لـ 5 خطوات، من غير خوف إنه يبوّظ حاجة.»

Any servant in the church, even one who did not build the panel, can make any daily edit in 3 to 5 steps, without
fear of breaking something. The report is built on a hands-on trial of the live panel, a read-only code review
(SWE) and sourced research (Researchy).

| Measure | From | To |
|---|---|---|
| Menu entries → groups | 25 | 7 |
| Steps of a daily task | 7–14 | 3–5 |
| Firebase plan | — | **Spark** (free plan only) |
| Servers needed | — | **0** |

"Ready for normal use" in this plan means exactly the report's success criteria (§١٣).

## ٢. الملفات (Files in this folder)

| File | What |
|---|---|
| [README.md](README.md) | this overview: goal, target design, decisions, roles, timeline, success criteria, conflict notes, sources |
| [SMALL-MODEL-GUIDE.md](SMALL-MODEL-GUIDE.md) | how the work is cut into packets that a smaller flash-class coding model can build safely; packet template; gates |
| [STAGE-0-live-data.md](STAGE-0-live-data.md) | «النهارده (0)» — items 1–5, manual actions on live data, no code |
| [STAGE-1-safety-and-custom-pages.md](STAGE-1-safety-and-custom-pages.md) | «المرحلة 1 — الأمان والصفحات المخصصة» — items 6–17 |
| [STAGE-2-clarity-and-fewer-steps.md](STAGE-2-clarity-and-fewer-steps.md) | «المرحلة 2 — الوضوح وتقليل الخطوات» — items 18–29 |
| [STAGE-3-remaining.md](STAGE-3-remaining.md) | «المرحلة 3 — الباقي» — items 30–35 |
| [STATUS.md](STATUS.md) | one checklist for all 35 items and every gate (tick as you go) |

## ٣. من يستخدم اللوحة (Who uses the panel)

The target user is a servant in the church office: comfortable with a phone and Facebook, **not** a programmer,
and does not know what Firebase or a slug is. Most of the work is six recurring tasks; the whole plan is about
making these faster and safer.

| # | Task | Today | Target | How |
|---|---|---|---|---|
| T1 | Edit a mass time | 4–5 steps | 3 | «عدّل المواعيد» button on the panel home |
| T2 | New notice or announcement | 6–8 | 4 | «+ إعلان» from the home, a preview, and a confirmation before sending to everyone |
| T3 | Reply to a visitor message | 4, and the reply happens outside the panel | 2 | the inbox opens on «محتاجة رد», with call and WhatsApp buttons and «تمّت» |
| T4 | Edit a service's phone | 7 | 3 | the phone is at the top of the form, not inside a closed card |
| T5 | Add a priest with a photo | 12–14 | 5 | photo, name and rank on top, date with a picker, English optional |
| T6 | Donations page | 10–13 | 5 | a ready «صفحة تبرعات» template; the link is made automatically |

Adding an admin takes 8+ steps today and needs Firebase. The e-mail invitation is **deferred**; the owner still
adds the admin from the panel and can stop or re-enable the account (item 12).

### نتيجة التجربة العملية (Hands-on trial as a new admin)

A priest, a service, a donations page, a section, an item and a notice were added; a mass time was changed and
restored; everything was deleted afterwards. Counts returned to what they were and the Monday mass returned to
07:00–08:30 as in the original data.

| Worked well | Confusing for a new user |
|---|---|
| Every delete asks for confirmation: «حذف هذا العنصر نهائيًّا؟» with a red «حذف» button | In the unsaved-changes message the prominent button is «تجاهل» (loses the work), not «متابعة التعديل» |
| The section-delete message explains what happens to the items inside | The browser Back button leaves the panel with no warning |
| «تم الحذف» appears after deleting | «إلغاء» in the new-announcement form closes at once without asking |
| Closing the editor with X while there are edits asks: «لديك تعديلات غير محفوظة. هل تريد تجاهلها؟» | In the priests list the icon taken for "edit" opens the public page; editing is by pressing the row itself |
| Error messages are Arabic and clear: «رقم غير صحيح (5–15 رقمًا)», «رابط غير صحيح (يبدأ بـ https://)», «هذا الرابط مستخدم بالفعل» | Errors show under the field only; no summary at the top says where to go |
| A trial notice appears on the public home page at once | The side menu sometimes stayed from an older screen |
| | The page once jumped by itself to another screen and letters were lost while typing — possibly slow painting; needs a retest on an ordinary device |
| | «حفظ وجدولة» was not tried (so no notification would be sent); the code review says there is no confirmation before sending |

## ٤. المبادئ (Principles the plan follows)

1. **المهمة الأول، مش الأرقام** — the first screen says what needs you today and holds the six task buttons, like
   Drupal CMS, which opens on the most important tasks.
2. **مفيش حاجة تضيع ومفيش حاجة تتبعت بالغلط** — a confirmation that names the item with a clear-verb button for
   what cannot be undone (sending to everyone), and undo for what can. This is NN/g's guidance.
3. **اعرض البسيط، وخبّي المتقدم** — important fields are open; English, order, slug and ID live under «خيارات
   متقدمة». Progressive disclosure, from NN/g and GOV.UK.
4. **كل سويتش بيقول حالته** — the word «ظاهر / مخفي» next to every switch, and it takes effect immediately. NN/g
   and Material 3.
5. **لغة الكنيسة مش لغة المبرمج** — no Firebase, UID, App Check or HH:mm in front of the ordinary user.
6. **عربي من الأساس** — full RTL, one numeral system, e-mails and links isolated from the Arabic text. Material
   bidirectionality and W3C ALReq.

## ٥. شكل القائمة الجديدة (Target menu)

25 entries become 7 groups. Duplicate names are merged and technical items stay with the owner only.

| Group | Contains |
|---|---|
| **الرئيسية** | محتاج انتباهك + المهام السريعة |
| **المواعيد** | القداسات، الاجتماعات، اليوم والبث، المواسم (فيها تجهيز الموسم) |
| **الإعلانات** | التنويهات، إعلان أو إشعار جديد، السجل |
| **الكنيسة** | الآباء (يخدم / متنيح)، الشفعاء، المحطات التاريخية، بيانات الكنيسة |
| **الخدمات والأنشطة** | الخدمات العامة، الأنشطة والكورالات، العيادات |
| **الصفحات** | الصفحة الرئيسية للموقع، الصفحات (بقوالب)، الأقسام وعناصرها في شاشة واحدة |
| **الرسائل** | رسائل الزوار بعداد اللي محتاج رد |
| **الإعدادات (للمالك)** | المشرفون، أنواع الرسائل، المساعد، إعدادات المواسم، متقدم: App Check وSentry وAPK والطوابير |

## ٦. شكل كل شاشة (Pattern of every screen)

1. A title and one help line at the top of every screen, e.g. «هنا مواعيد القداسات الأسبوعية. التعديل بيظهر على
   الموقع على طول». The code review says one field in the code covers the 14 lists.
2. Every list row carries a written state: ظاهر, مخفي, منتهي or «بيانات تجريبية». The trash icon moves away from
   the eye icon and gets a name.
3. Pressing the row opens editing; the «افتح في الموقع» icon is clearly an external link.
4. In the form the basic fields are open at the top: name, photo, phone and time. English, order and links sit
   under «خيارات متقدمة».
5. A fixed bar at the bottom: «فيه تعديلات مش محفوظة · حفظ · إلغاء». In the leave message «متابعة التعديل» is the
   prominent button.
6. A warning if the user presses browser Back or closes the tab with edits.
7. Dates use a picker with Arabic month names and still allow typing; time is 12-hour (ص / م) everywhere.
8. On a save error: a summary on top, «فيه حقلين محتاجين تصحيح», each entry taking you to its field.
9. Empty lists say what to do, e.g. «مفيش أقسام لسه · + أضف أول قسم».
10. The link (slug) is made automatically from the title and can be edited only under «متقدم».

## ٧. الأمان من الغلط (Safety from mistakes)

| Action | Today | Proposed |
|---|---|---|
| Delete an item | generic confirmation | confirmation with the item's name, or a deleted-items bin with «تراجع» for 10 seconds |
| Send a notification to everyone | no confirmation, per the code | summary «هيتبعت لكل المشتركين دلوقتي: [العنوان]» and an «ابعت للكل» button |
| Apply a season | has a confirmation | add a summary of the changes and «تراجع عن آخر تطبيق» |
| Leave with edits | warning, but the wrong button is prominent | «متابعة التعديل» is the primary button; warn on browser Back and tab close |
| Replaces the day's masses | no notice | preview: «القداسات دي مش هتظهر يوم كذا» |
| Public switches (stream, notifications, unconfirmed data) | no words | written state, and a warning if the stream is on with an empty link |
| Who edited what | last edit only | «آخر تعديل» (who and when) stays clearly visible, with no full log |

**Undo or confirmation — both, each in its place:**

| Kind of action | Approach | Why |
|---|---|---|
| Delete an item (priest, service, notice, page) | deleted at once; «اتمسح · تراجع» shows for 10 seconds | faster, and does not train the user to press "OK" without reading; NN/g prefers undo for reversible actions |
| Send to everyone, apply a season, clear the log | confirmation with the item's name and a clear-verb button («ابعت للكل») | a notification cannot be recalled once it reaches phones |
| Stop an admin | simple confirmation | reversible with one press, but it affects a person |

The 10-second undo needs no server: the real delete is postponed until the time ends. Together with «آخر تعديل»
this is enough for an office with few admins, so no full change log is built.

## ٨. المشرفين والجلسات والتعلّم (Admins, sessions, learning)

| Topic | State | What the report says |
|---|---|---|
| Invite an admin by e-mail | **مؤجلة** | not done now; if needed later, the existing Cloudflare Worker can do it at no cost |
| «محرر مؤقت» that is switched off and on | **اتقرر** | for an employee or occasional servant: the owner has a «نشط / موقوف» switch on every admin; a stopped account cannot edit anything, is not deleted, and returns with one press; an optional end date can be set. Needs an `active` field in `admins/{uid}` checked by the Firestore rules. No server; runs on Spark |
| Session | **سهل** | «افتكرني» on a personal device; automatic sign-out after 15–30 minutes without use on the shared office device, with a warning before it, as OWASP and NIST recommend. Name and permission already show in the menu |
| No onboarding tour | **اتقرر** | no tour and no «؟» button; the help line under each screen title and the written state next to each switch are enough for the interface to explain itself |
| Trial session with a real servant | — | after the first stage, sit with a servant who has never seen the panel, hand over the six tasks without help and record where they stop; repeat after every stage |

## ٩. الإنجليزي ميزة تتفعل وتتقفل (English as a switchable feature — Kerollos's decision, 12 November 2026)

One switch in the settings: «النسخة الإنجليزية». Only the owner can change it.

- **When off:** every English field disappears from every form, is not required, and takes no part in validation
  or error messages. The EN button disappears from the public site. Forms become about half as long.
- **When on again:** the fields return with the data recorded before; nothing is deleted. Items missing their
  English show in «محتاج انتباهك».
- **In the code (decided):** a `lang: en` mark on `FieldDef` in `admin_schema.dart`; `DocEditor` ignores marked
  fields while the feature is off. Fields ending in `En` must stay optional in the Firestore rules. Size M, no
  server.

## ١٠. القرارات (Decisions)

| Decision | State |
|---|---|
| **Spark only.** No Blaze. The temporary editor works with ordinary Firestore rules. The tour, the «؟» button and the full change log are removed; the e-mail invitation is deferred and, if needed, runs on the Cloudflare Worker at no cost | اتقرر |
| **The temporary editor edits all content**, with no per-section limits. Settings and admins stay owner-only as they are | اتقرر |
| **English data stays stored when the feature is off**; it is not deleted now, and the decision is revisited later | اتقرر |
| Removed from the plan: tour, «؟» button, full change log (the help line and «آخر تعديل» are enough) | اتشال — 12 November |
| E-mail invitation of admins | مؤجلة — 12 November |

## ١١. خريطة المراحل (Stage map)

The unified work list (last reviewed 13 November 2026 against the current code after PR #70,
`docs/memory-bank` and the admin-panel trial report) is the single list of work, ordered by priority: 5 fixes on
live data, 28 open tasks in the code, 8 done or removed, 1 deferred by decision. No simplification code has changed
since 12 November; the three stages have not started. The older trial report stays where it is, unedited.

| Stage | Items | Objective | Start gate | End gate | Estimate (planning estimate) |
|---|---|---|---|---|---|
| **0 — النهارده** | 1–5 | fix the live data by hand | owner signed in to `/admin` | G0 | one working session of the owner + office follow-up |
| **1 — الأمان والصفحات المخصصة** | 6–17 | nothing is lost, nothing is sent by mistake; custom pages in fewer steps | G0 passed | G1 | 2–4 weeks |
| **2 — الوضوح وتقليل الخطوات** | 18–29 | 7 menu groups, new home, open fields, inbox, English switch | G1 passed | G2 | 2–4 weeks |
| **3 — الباقي** | 30–35 | church info, message types, optional items, trial, deferred invite | G2 passed | G3 = ready for normal use | 1–2 weeks |

Categories used in the list: **خطة التبسيط** · **الصفحات المخصصة** · **تحسينات أخرى**. Priority 1 before 2, then 3.
Infrastructure items such as Sentry, Android and the domain stay in `docs/memory-bank/11-open-tasks.md`.

The report sizes the code work S (small), M (medium), L (large) from the SWE review, with the suggested order
`k, e, m, d, b, c, g, h, a, j`, then `i` and `l` (the letters are the review's own item labels; the report does
not expand them).

## ١٢. الأدوار (Roles and responsibilities)

| Role | Who | Responsible for |
|---|---|---|
| **Owner** | Kerollos | decisions (already recorded in §١٠), Stage 0 actions on live data, gate approvals, the only account that changes «النسخة الإنجليزية» and admin status |
| **Church office** | office servants | office tasks: items 4, 5, 35; content for the donations page; never invented by the implementer |
| **Implementer** | a smaller flash-class coding model, one packet at a time ([SMALL-MODEL-GUIDE.md](SMALL-MODEL-GUIDE.md)) | code, tests, memory-bank and Arabic documentation updates inside each PR |
| **Reviewer** **(proposed)** | the owner, or a stronger reviewing agent acting for the owner | reviews every PR against the packet's acceptance list; runs the stage gate |
| **Trial servant** | a servant who has never seen the panel | performs the six tasks without help at each stage gate |

## ١٣. كيف نعرف أننا نجحنا (Success criteria — "ready for normal use")

| # | Criterion | Measured by | State on 12 November |
|---|---|---|---|
| S1 | A new servant finishes the six tasks without help in under 15 minutes | timed trial session | not tried yet |
| S2 | Every daily task takes 5 steps or fewer | step count per task T1–T6 against §٣ | — |
| S3 | Not one English or technical word in front of the ordinary editor | walkthrough as an editor with the dashboard in Arabic | — |
| S4 | No irreversible action without a confirmation that names the item | checklist of §٧ actions | — |
| S5 | Stopping or re-enabling an admin from the panel with one press | owner performs it; rules test proves a stopped account cannot write | — |

Acceptance of the whole phase = S1–S5 all met at gate G3, on the Spark plan with no server.

## ١٤. الاعتمادات الحرجة (Timeline and critical dependencies)

- Stage 0 comes before any code: the report's «قبل أي حاجة» — delete the offensive notification from the log,
  fix the stream switch, decide which sample data stays visible.
- The fixes change shared parts (`admin_schema.dart`, `collection_list.dart`, `doc_editor.dart`), so one change
  repairs 14 screens at once. Any change of names must change, in the same PR, the tests that depend on the
  element keys, and update the memory bank.
- Item 12 (admin «نشط / موقوف») needs the `active` field and Firestore rules before the UI switch ships.
- Item 15 (donations template) should land before the office finishes item 4, but item 4 can be done today with
  the existing page editor.
- Item 23 («محتاج انتباهك») lists items missing English only once item 27's switch exists.
- Item 33's trial depends on Stage 1 being live; the report repeats the trial after every stage.
- Total **(planning estimate)**: 5–10 weeks of one implementer lane with review, after G0. The report gives sizes
  only; it sets no dates.

## ١٥. ملاحظات حل التعارض (Conflict-resolution notes)

| # | Discrepancy inside the report | Resolution path |
|---|---|---|
| C1 | The «المراحل» section lists "quick wins (S) → safety and clarity (M) → new home (M)", while the unified list orders the same work as safety first (items 6–17), then clarity (18–29), then the rest (30–35) | The unified list is the later review (13 November) and calls itself the single work list; it governs order. The S/M sizes stay as size hints |
| C2 | "25 → 7 groups", yet the target menu shows the seven groups plus «الإعدادات (للمالك)» | Build it as drawn: seven groups for every admin, plus the owner-only settings group |
| C3 | Delete is described as "confirmation with the name, **or** a bin with undo" (§٧ table), as "deleted at once with 10-second undo" (decision), and as "undo, and the confirmation names the item" (item 8) | Item delete = immediate with a 10-second «اتمسح · تراجع» that names the item; confirmations that remain (section delete, send to everyone, apply season, clear log) name the item |
| C4 | Automatic sign-out is a range, 15–30 minutes, not one value | One configurable constant; the owner picks the value at the Stage 1 start gate |
| C5 | Item 17 has priority 2 but sits inside Stage 1 (items 6–17) | Schedule it last in Stage 1; it may move to Stage 2 without blocking G1 |
| C6 | "Settings and admins stay owner-only as they are", while only the admins screen is owner-only today and the menu moves message types, the assistant and season settings into «الإعدادات (للمالك)» | Group visibility follows the target menu. The only rules change the report states is `admins.active`; the owner confirms before item 18 starts whether the moved screens also become owner-only in the rules |
| C7 | Item 28 wants the sitemap updated without waiting for a deploy, under "Spark only, 0 servers", and names no mechanism | Start the item with a short design note limited to what already exists; no new paid service. The owner approves the note before code |
| C8 | The trial session is "after the first stage" and repeated after every stage, while item 33 has priority 3 | A trial runs at every stage gate; item 33 in Stage 3 is the final recorded session plus the 320px check |
| C9 | The report gives sizes (S/M/L) but no durations or dates | Durations in this plan are planning estimates for the owner to confirm |

## ١٦. خارج النطاق (Out of scope)

Onboarding tour · «؟» button · full change log · Blaze plan · any new server · e-mail invitation of admins
(deferred; Cloudflare Worker if ever needed) · infrastructure items kept in `docs/memory-bank/11-open-tasks.md`.

## ١٧. المصادر (Sources)

1. Hands-on trial on https://maximos-domadios-church.web.app/admin on 12 November 2026 (everything added was
   deleted afterwards)
2. Read-only review of the church-portal code by SWE, 12 November 2026
3. https://www.nngroup.com/articles/confirmation-dialog/ — NN/g: Confirmation Dialogs
4. https://www.nngroup.com/articles/toggle-switch-guidelines/ — NN/g: Toggle Switch Guidelines
5. https://www.nngroup.com/articles/progressive-disclosure/ — NN/g: Progressive Disclosure
6. https://www.nngroup.com/articles/date-input/ — NN/g: Date Input
7. https://www.nngroup.com/articles/form-design-placeholders/ — NN/g: Placeholders in Form Fields
8. https://m3.material.io/components/switch/guidelines — Material 3 Switch
9. https://m3.material.io/foundations/layout/understanding-layout/bidirectionality-rtl — Material 3 Bidirectionality
10. https://ghost.org/help/managing-your-team/ — Ghost: Managing your team (invitation by e-mail)
11. https://ghost.org/changelog/post-history/ — Ghost: Post history
12. https://project.pages.drupalcode.org/drupal_cms/get-started/getting-around/ — Drupal CMS: Getting around
13. https://firebase.google.com/docs/auth/admin/email-action-links — Firebase: Email action links
14. OWASP Session Management Cheat Sheet —
    https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
15. https://design-system.service.gov.uk/components/details/ — GOV.UK Design System: Details
16. Review of the code and `docs/memory-bank` on 13 November 2026 on church-portal after PR #70, merging the open
    issues of the admin-panel trial report (12 November)
