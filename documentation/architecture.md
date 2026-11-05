# البنية العامة للتطبيق

هذا الملف يشرح كيف يتركّب التطبيق من الداخل: هيكل كود Flutter، التوجيه بين الصفحات، Firebase وقاعدة البيانات
وقواعد الأمان، طريقة تحميل البيانات (الذاكرة المؤقتة أولًا)، النسخة المدمجة الاحتياطية، الاستضافة، ومسارات
CI/CD. التفاصيل الأعمق بالإنجليزية في [`docs/memory-bank/03-architecture.md`](../docs/memory-bank/03-architecture.md)
و [`04-data-model.md`](../docs/memory-bank/04-data-model.md) و [`05-firebase.md`](../docs/memory-bank/05-firebase.md).

## 1. الصورة الكبيرة

```
الزائر (متصفح أو تطبيق Android)
        │
        ▼
 Firebase Hosting (الموقع maximos-domadios-church)  ──►  ملفات Flutter web المبنية (build/web)
        │
        ├── Cloud Firestore  ← كل المحتوى والإعدادات ورسائل التواصل
        ├── Firebase Auth    ← دخول المشرفين فقط (بريد + كلمة مرور)
        ├── App Check        ← reCAPTCHA Enterprise على الويب / Play Integrity على Android
        ├── Firebase AI Logic (Gemini) ← المساعد الذكي «اسأل الكنيسة»
        └── Sentry (خدمة خارجية) ← تقارير الأعطال التقنية فقط، بدون بيانات شخصية
```

- **الخطة: Spark (مجانية)**. لذلك: لا Cloud Functions، والصور المرفوعة تُخزَّن داخل Firestore نفسها
  (مجموعة `media`) بدل Cloud Storage. انظر [features/images-and-media.md](features/images-and-media.md).
- قاعدة البيانات Firestore في `europe-west1`.

## 2. هيكل كود Flutter (`lib/`)

| المجلد | المحتوى |
|---|---|
| `lib/main.dart` | نقطة البداية: `ErrorReporting.run(_start)` (Sentry)، تحميل النسخة المدمجة `SeedData.load()` وتشغيل Firebase معًا، ثم اختيار مصدر البيانات |
| `lib/app.dart`, `lib/router.dart` | التطبيق، الثيم، والتوجيه (`go_router`) |
| `lib/config/app_config.dart` | ثوابت البناء: نموذج Gemini الافتراضي، مفتاح reCAPTCHA، DSN الخاص بـ Sentry، مسار `/admin` |
| `lib/core/` | الترجمة `l10n.dart`، الثيم `theme.dart`، حفظ اللغة، وسم `<html lang>` والـ canonical، بيئة الحركة |
| `lib/domain/` | **منطق العمل بلغة Dart خالصة** مع اختبارات: الجداول وتوقيت القاهرة (`CairoTime`)، `features.dart`، الثيمات، آية اليوم، المساعد، الخصوصية في تقارير الأخطاء… |
| `lib/data/` | الاتصال بـ Firebase: `content_repository.dart` (القراءة العامة)، `admin_repository.dart` (كتابة المشرفين)، `media_repository.dart`، `error_reporting.dart`، `app_check_providers.dart` |
| `lib/state/providers.dart` | مزودات Riverpod 3 التي تربط البيانات بالواجهة |
| `lib/ui/pages/` | الصفحات العامة |
| `lib/ui/admin/` | لوحة التحكم (`admin_page.dart`, `admin_schema.dart`, `features_editor.dart`…) |
| `lib/ui/widgets/` | العناصر المشتركة: الهيكل والقائمة والتذييل `app_shell.dart` و `common.dart`، الواجهة والفيديو، الخريطة، الصور |

قواعد مهمة للمطورين (من `AGENTS.md`): أي تغيير في حقل يلمس **أربعة أماكن معًا**: النموذج في `lib/domain/`،
مخطط لوحة التحكم `lib/ui/admin/admin_schema.dart`، `firestore.rules`، ومولّد البذور `tool/gen_seed.py` (+ الاختبارات).
كل منطق الوقت يمر عبر `CairoTime` (توقيت Africa/Cairo)، والأيام بترقيم ISO من 1 إلى 7، والأوقات بصيغة `"HH:mm"`.

## 3. التوجيه (الصفحات والروابط)

التوجيه في `lib/router.dart` بروابط نظيفة بدون `#` (`usePathUrlStrategy`)، والاستضافة تعيد أي رابط إلى `index.html`.

| الرابط | الصفحة | القسم الذي يتحكم فيه |
|---|---|---|
| `/` | الرئيسية | لا يُغلق أبدًا |
| `/about` | عن الكنيسة | `history` أو `saints` أو `priests` أو `departedPriests` (يكفي واحد مفعّل) |
| `/mass-schedule` | مواعيد القداسات | `schedule` |
| `/church-education` | التربية الكنسية والاجتماعات | `meetings` |
| `/church-activities` | الأنشطة والكورالات | `activities` |
| `/clinics` | العيادات (`?specialty=` اختياري) | `clinics` |
| `/public-services` | الخدمات العامة | `services` |
| `/contact` | تواصل معنا | `contactInfo` أو `socials` أو `contactForm` |
| `/section/<slug>` | قسم مخصص | `customSections` + `visible` للقسم |
| `/page/<slug>` | صفحة مخصصة | `customPages` + `visible` للصفحة |
| `/church-education/<id>` وغيرها | صفحة تفاصيل عنصر | نفس قسم الصفحة الأم |
| `/ask` | المساعد الذكي (يُحمَّل كجزء منفصل فقط عند تفعيله) | `assistant` |
| `/admin` | لوحة التحكم (جزء منفصل، لا يظهر في محركات البحث) | — |

- كل صفحة عامة ملفوفة بـ `FeatureGate`: إذا كان قسمها موقوفًا تظهر رسالة «هذا القسم غير متاح حاليًا».
- رابط غير موجود يعرض صفحة «غير موجودة» مع زر العودة للرئيسية (`noindex`).
- اللغة في الرابط: الإنجليزية تضيف `?lang=en`، والعربية بدون أي معامل (الرابط الأساسي). انظر
  [features/localization.md](features/localization.md).
- `/admin` و `/ask` «مؤجلان» (deferred): ملفات JavaScript منفصلة لا يحمّلها الزائر العادي.

## 4. Firestore: المجموعات والحقول الرئيسية

| المجموعة / المستند | المحتوى | القراءة | الكتابة |
|---|---|---|---|
| `liturgies` | القداسات والعشيات والتسابيح | عامة | مشرف |
| `seasons` | المواسم (أسبوع الآلام، القيامة، الميلاد، النهضات…) | عامة | مشرف |
| `meetings` | الاجتماعات ومدارس الأحد | عامة | مشرف |
| `clinics` | العيادات (القسم موقوف منذ 4 نوفمبر 2026) | عامة | مشرف |
| `facilities` | الخدمات العامة | عامة | مشرف |
| `activities` | الأنشطة والكورالات | عامة | مشرف |
| `priests` | الآباء الكهنة (`status`: `serving` / `departed`) | عامة | مشرف |
| `saints` | الشفعاء | عامة | مشرف |
| `milestones` | محطات «قصتنا» | عامة | مشرف |
| `alerts` | التنويهات العاجلة | عامة | مشرف |
| `categories`, `entries`, `pages` | الأقسام المخصصة وعناصرها والصفحات المخصصة | عامة | مشرف |
| `settings/church` | بيانات الكنيسة (الاسم، العنوان، الهواتف، التواصل الاجتماعي، التاريخ، المذابح، `assistantEnabled`) — وهو أيضًا **علامة أن القاعدة مُعبّأة** | عامة | مشرف |
| `settings/features` | مفاتيح الأقسام وترتيب الرئيسية والواجهة والثيمات وآية اليوم والتذييل و`errorReporting` | عامة | مشرف |
| `settings/contact` | أنواع رسائل التواصل | عامة | مشرف |
| `settings/assistant` | إعدادات المساعد الذكي | عامة | مشرف |
| `media/{id}` | الصور المرفوعة (بايتات مضمّنة) | قراءة مستند واحد عامة، القائمة للمشرف | مشرف |
| `contact_messages` | رسائل الزوار | **مشرف فقط** | الزائر ينشئ فقط (بشروط)، المشرف يعدّل الحالة والملاحظات ويحذف |
| `meta/contact_rate` | عدّاد منع الإغراق لنموذج التواصل | لا أحد | مع كل رسالة فقط |
| `admins/{uid}` | المشرفون `{email, role}` | صاحب الحساب نفسه أو المالك | المالك فقط (ولا يغيّر نفسه) |

حقول مشتركة في معظم العناصر: `visible` (إخفاء دون حذف)، `order` (الترتيب)، `sample` (بيانات غير مؤكدة؛ تظهر
في لوحة التحكم فقط منذ PR #39، ولا علامة لها في الموقع العام)، وحقول ثنائية اللغة بنمط `nameAr` / `nameEn`.

## 5. قواعد الأمان (`firestore.rules`)

- `isAdmin()` = مستخدم مسجّل وله مستند في `admins/{uid}`؛ `isOwner()` = نفس الشيء و `role == 'owner'`.
- كل كتابة من المشرف **مُتحقَّق منها** بدوال `validContent` و `validChurch` و `validFeatures` و
  `validContactSettings` و `validAssistant`: قائمة مفاتيح مسموح بها، أنواع، وأطوال قصوى. حقل جديد لا يُضاف للقواعد =
  الحفظ يفشل بـ `permission-denied`.
- الزائر لا يستطيع قراءة الرسائل أبدًا، ويستطيع إنشاء رسالة فقط مع تحديث `meta/contact_rate` في نفس الدفعة،
  ولا يتقدم هذا العدّاد إلا مرة كل **10 ثوانٍ** على مستوى الموقع كله.
- مستندات `settings` لا تُحذف أبدًا.
- اختبارات القواعد في المحاكي: `tool/rules_test/rules.test.mjs` (تعمل في CI).

## 6. طريقة تحميل البيانات: الذاكرة المؤقتة أولًا

Firestore في المتصفح يحتفظ بنسخة محلية (cache). عند فتح الصفحة يرد أولًا من النسخة المحلية ثم من الخادم بعد
لحظات. التطبيق يتعامل مع هذا هكذا (`lib/data/content_repository.dart`):

- **الأقسام الأساسية** (القداسات، الاجتماعات، الآباء…): تُعرض أول قراءة فورًا (حتى لو من الذاكرة المحلية) لأن لها
  نسخة مدمجة احتياطية، ثم تتحدث تلقائيًا.
- **المحتوى المخصص** (`categories` و `entries` و `pages`): ليس له نسخة مدمجة، لذلك يستخدم `settleFirst`
  (PR #23): يتجاهل القراءات القادمة من الذاكرة المحلية فقط حتى يرد الخادم، أو لمدة أقصاها **8 ثوانٍ**، ثم يعرض
  آخر قراءة محفوظة. هذا يمنع ظهور «هذه الصفحة غير متاحة حاليًا» خطأً عند فتح رابط مباشر، ويمنع بقاء الهياكل
  الرمادية للأبد.
- **مستندات الإعدادات** (`settings/features` و `settings/contact` و `settings/assistant`): المستند المخزَّن «يثبت
  نفسه» ويحلّ محل القيم الافتراضية في الكود حتى لو لم يُجب فحص التعبئة (PR #23).

## 7. النسخة المدمجة الاحتياطية (seed fallback)

- الملف `assets/seed/seed.json` مدمج داخل التطبيق ويُولَّد من `tool/gen_seed.py` (لا يُعدَّل يدويًا).
- عند كل اشتراك في بيانات، يتحقق التطبيق من وجود `settings/church` (مهلة 8 ثوانٍ). إن لم يُجب الفحص أو كانت
  القاعدة غير مُعبّأة أو انقطع الاتصال: يُعرض المحتوى المدمج **ويبقى الاشتراك مفتوحًا**، فإذا وصلت بيانات حقيقية
  تحل محله.
- إن لم يكن Firebase متاحًا أصلًا (`SeedRepository`) يعمل الموقع كله على النسخة المدمجة، ونموذج التواصل لا يرسل.
- أثناء عرض أي جزء من النسخة المدمجة يظهر في التذييل: «تعرض البيانات المحفوظة مع التطبيق».
- **إثبات التعبئة مشترك بين كل البيانات (PR #30، ADR-038)**: مستمع `settings/church` المباشر، بمجرد أن يرى المستند
  موجودًا، يُعلم الفحص (`SeedGate.markSeeded`)، فيترك كل تيار ما زال على النسخة المدمجة القيمة الحقيقية التي وصلته
  (`whenSeeded`). كان سبب ظهور الرسالة على الموقع المباشر رغم عمل Firestore: فحص `settings/church` ينتهي مهلته (8
  ثوانٍ) أو يرد «client is offline» عند بداية بطيئة، والتيار الذي لا تثبت قيمته نفسها (مستند اختياري غير موجود مثل
  `settings/contact` أو مجموعة فارغة) لا يصله من Firestore إلا لقطة واحدة، فيبقى على النسخة المدمجة للأبد.

## 8. الاستضافة والتحويل من الرابط القديم (`firebase.json`)

- هدفان في Hosting:
  - `app` → موقع `maximos-domadios-church` يقدّم `build/web` مع إعادة كل الروابط إلى `index.html`.
  - `legacy-redirect` → موقع `asafra-church-portal` يحوّل أي رابط بتحويل دائم **301** إلى
    `https://maximos-domadios-church.web.app/<نفس المسار>`.
- الترويسات: `Cache-Control: no-cache` للصفحات، وتخزين **7 أيام** للصور والخطوط و `canvaskit`، مع ترويسات أمان
  (`X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`, HSTS, `Permissions-Policy`). لا توجد CSP؛ إن
  أُضيفت يجب أن تسمح بـ `browser.sentry-cdn.com` و `*.ingest.de.sentry.io`.

## 9. CI/CD (`.github/workflows/`)

| المسار | متى يعمل | ماذا يفعل |
|---|---|---|
| `ci.yml` | كل push على أي فرع، وكل PR | `flutter analyze` ← `flutter test` ← بناء الويب (بيئة Sentry `ci`) ← تبصيم خطوط الأيقونات `tool/fingerprint_icon_fonts.py` ← التحقق من `seed.json` وأنه مطابق لمولّده؛ ووظيفة ثانية `firestore-rules` تشغّل اختبارات القواعد في المحاكي |
| `deploy.yml` على PR | كل PR من نفس المستودع | `build` (اختبارات + بناء بيئة `preview` **بدون مفتاح reCAPTCHA**، لذلك المساعد مخفي في المعاينة) ← `preview`: نشر على قناة معاينة `pr-<رقم>` لمدة 7 أيام وتعليق بالرابط على الـ PR |
| `deploy.yml` على `main` | بعد الدمج | `build` (بيئة `production` مع `RECAPTCHA_SITE_KEY`) و `rules-test` ← `deploy-rules` (قواعد وفهارس Firestore، بيئة `production`) ← `deploy-live` (Hosting للموقع والتحويل القديم، ينتظر نشر القواعد أولًا) |
| `seed.yml` | يدويًا فقط (Run workflow) | يرفع `seed.json` إلى Firestore. المدخلات: `admin` (UID:email)، `admin_email`، `only` (مجموعات مفصولة بفواصل)، `fill_missing`، `force` |

- السر الوحيد المطلوب: `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL` (مفتاح حساب خدمة JSON). متغيرات المستودع:
  `RECAPTCHA_SITE_KEY` (موجود)، و `SENTRY_DSN` اختياري (غير موجود؛ البناء يستخدم الـ DSN العام في الكود).
- **تحذير مهم:** لا تشغّل `seed.yml` بخيار `force` على الإنتاج أبدًا (يستبدل تعديلات المشرفين). وحتى بدون `force`
  البذر **يعيد إنشاء أي مستند محذوف** موجود في `seed.json` (مثل العيادات الـ 11 التي حذفها المالك). التفاصيل في
  [operations.md](operations.md).
- الدمج إلى `main` يكون **Squash merge** بعد نجاح CI، ولا يُدفع إلى `main` مباشرة.

## 10. الاختبارات

- `flutter test` (المجلد `test/`): منطق المجال، البذور، صلاحيات القواعد من جهة الواجهة، لوحة التحكم، سهولة الوصول
  (320 بكسل × تكبير نص 200%)، الثيمات وتباين الألوان، المساعد، Sentry…
- في بيئة بها proxy: `export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost` قبل الاختبارات.
- اختبارات القواعد: `cd tool/rules_test && npm ci && npm test` (تحتاج Java 11+).
