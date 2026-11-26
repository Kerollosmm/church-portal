# تطبيق الويب (PWA) والتخزين المؤقت وتبصيم خطوط الأيقونات

## ماذا تقدم للزائر

- يمكن إضافة الموقع للشاشة الرئيسية للهاتف («إضافة إلى الشاشة الرئيسية») فيفتح كتطبيق مستقل بأيقونة ختم الكنيسة
  واسم «كنيسة مكسيموس ودوماديوس».
- شاشة بداية بلوحة الواجهة واسم الكنيسة أثناء التحميل (ADR-037، انظر [performance-pagespeed.md](performance-pagespeed.md))، ورسالة واضحة إذا فشل التحميل.
- بعد كل نشر جديد يرى الزائر النسخة الجديدة دون الحاجة لمسح ذاكرة المتصفح.

## التحكم من لوحة التحكم

لا شيء؛ كلها إعدادات بناء ونشر.

## كيف تعمل تقنيًا

- `web/manifest.json`: الاسم، `display: standalone`، الألوان، الأيقونات العادية و maskable (192/512). كل الأيقونات تُولَّد
  من الختم بـ `tool/gen_branding.sh`.
- **الخطوط مدمجة** في التطبيق (`assets/fonts/`: IBM Plex Sans Arabic، Lalezar، Aref Ruqaa — رخصة SIL OFL)، بدون
  تحميل من Google Fonts، ويُحمَّل الخطان الأساسيان مسبقًا (`preload`) في `index.html`.
- **ترويسات الاستضافة** (`firebase.json`): الصفحات و`index.html` و`flutter_bootstrap.js` و`FontManifest.json` بـ `no-cache, no-store, must-revalidate` أو `no-cache` (تُفحص كل مرة)، والصور والخطوط و`canvaskit` تُخزَّن **7 أيام**. أما الحزمة الرئيسية المُبصَّمة `/main.*.dart.js` فتُخزَّن بشكل دائم (`public, max-age=31536000, immutable`) دون إعادة تحميل للزائر العائد، بينما تبقى ملفات `main.dart.js_*.part.js` والنسخة غير المبصّمة `main.dart.@(js|mjs|wasm)` على `no-cache`. وتستبعد الاستضافة ملفات الاختبار (`**/*.test.mjs`) وملفات `**/README.md`. إعادة التوجيه إلى `index.html` للمسارات التي بلا امتداد (ولمسارات الأقسام والصفحات وصفحات التفاصيل)، أما الروابط التي تنتهي بامتداد ملف (مثل `.json` أو `.map`) ولا يوجد لها ملف فترجع 404.
- **تبصيم الحزمة الرئيسية (PR 6G، ADR-088)**: الأداة `tool/fingerprint_web_bundle.py` (تعمل في `ci.yml` و`deploy.yml` بعد البناء) تعيد تسمية `main.dart.js` و`main.dart.js.map` فقط إلى `main.<sha256[:12]>.dart.js` (و`.map`) وتحدّث `flutter_bootstrap.js` و`sourceMappingURL`، مع إبقاء ملفات `main.dart.js_*.part.js` كما هي لأن أسماءها مدمجة داخل `main.dart.js`.
- **تبصيم خطوط الأيقونات (PR #23)**: Flutter يقلّص خط الأيقونات `MaterialIcons-Regular.otf` (و `CupertinoIcons.ttf`)
  للأيقونات المستخدمة فقط ويكتبه **بنفس الاسم** كل بناء؛ مع تخزين 7 أيام كانت الهواتف تحتفظ بنسخة قديمة فتظهر الأيقونات
  الجديدة فارغة. الأداة `tool/fingerprint_icon_fonts.py` تعيد تسمية كل خط إلى `<name>.<sha256[:12]>.<ext>` وتحدّث
  `assets/FontManifest.json`، فيتغير الرابط مع كل تغيير. تعمل في `ci.yml` و `deploy.yml` بعد `flutter build web`.
- `/admin` و `/ask` ملفات JavaScript منفصلة (deferred) لا يحمّلها الزائر العادي.
- عامل الخدمة (service worker) الذي يولّده Flutter حاليًا هو عامل «تنظيف» يلغي تسجيل نفسه (Flutter أوقف دعمه)، لذلك
  **لا يوجد عمل دون اتصال** بالمعنى الكامل؛ الذي يعمل دون اتصال هو المحتوى المدمج الاحتياطي وذاكرة Firestore المحلية.

## الحدود والمشاكل المعروفة

- لا توجد نافذة «تثبيت التطبيق» مخصصة (الـ manifest فقط).
- الخطوط غير مقلّصة (subset) — حجمها كامل.
- لا توجد ميزانية أداء (Lighthouse) في CI (نتائج PageSpeed في [performance-pagespeed.md](performance-pagespeed.md)).
