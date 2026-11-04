# توثيق بوابة كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود

هذا المجلد يشرح **كيف يعمل التطبيق** بلغة بسيطة: ماذا يرى الزائر، وكيف يتحكم المشرف في كل شيء من لوحة
التحكم `/admin`، وكيف تعمل كل ميزة من الداخل، وما حدودها المعروفة. هو مكتوب لصاحب المشروع ولمكتب الكنيسة ولأي
مطوّر جديد ينضم للمشروع.

- الموقع المباشر: <https://maximos-domadios-church.web.app>
  (الرابط القديم `asafra-church-portal.web.app` يحوّل تلقائيًا إلى الرابط الجديد).
- لوحة التحكم المخفية: <https://maximos-domadios-church.web.app/admin>
- مشروع Firebase: `asafra-church-portal` (خطة Spark المجانية).
- المستودع: `Kerollosmm/church-portal`.

## ما هو التطبيق؟

بوابة عامة **باللغة العربية أولًا** (من اليمين لليسار) مع زر للتبديل إلى الإنجليزية، لكنيسة قبطية أرثوذكسية في
نهاية شارع 45، العصافرة قبلي، الإسكندرية. يجيب الموقع عن أسئلة الزائر اليومية في ثوانٍ: موعد القداس القادم،
الاجتماعات، الأنشطة، الخدمات، الآباء الكهنة، العنوان والخريطة، ونموذج مراسلة، ومساعد ذكي «اسأل الكنيسة».

- **ليس نظام إدارة كنيسة**: لا توجد حسابات للزوار ولا بيانات شخصية للمخدومين. الحسابات للمشرفين فقط.
- مبني بـ **Flutter** (يعمل على الويب و Android، وجاهز لـ iOS لاحقًا) و **Firebase**
  (Firestore لقاعدة البيانات، Hosting للاستضافة، Auth لدخول المشرفين، App Check، و Firebase AI Logic للمساعد).
- كل المحتوى قابل للتعديل من `/admin` دون الحاجة لمبرمج.

## كيف تقرأ هذا التوثيق؟

1. ابدأ بـ [architecture.md](architecture.md) لتفهم الصورة الكاملة (10 دقائق).
2. افتح ملف الميزة التي تهمك من الجدول بالأسفل. كل ملف فيه أربعة أجزاء ثابتة:
   - **ماذا تقدم للزائر**
   - **التحكم من لوحة التحكم** (أسماء الشاشات والمفاتيح كما تظهر فعلًا في `/admin`)
   - **كيف تعمل تقنيًا** (الملفات، مجموعات Firestore والحقول، قواعد الأمان، المفاتيح في `settings/features`)
   - **الحدود والمشاكل المعروفة**
3. للنشر وإضافة مشرف وتشغيل البذر (seed) بأمان ومتابعة الأخطاء والمشاكل الشائعة: [operations.md](operations.md).

> أسماء الملفات والمسارات والحقول ومجموعات Firestore مكتوبة بالإنجليزية كما هي في الكود (مثل `settings/features`)
> حتى يسهل البحث عنها.

## فهرس الميزات

| الميزة | الملف |
|---|---|
| الصفحة الرئيسية والواجهة (الفيديو، الحركة، الكتل) | [features/home-and-hero.md](features/home-and-hero.md) |
| آية اليوم | [features/daily-verse.md](features/daily-verse.md) |
| ثيمات المناسبات والألوان | [features/occasion-themes.md](features/occasion-themes.md) |
| مواعيد القداسات والمواسم والقداس القادم | [features/mass-schedule-and-seasons.md](features/mass-schedule-and-seasons.md) |
| التربية الكنسية والاجتماعات | [features/meetings.md](features/meetings.md) |
| العيادات | [features/clinics.md](features/clinics.md) |
| عن الكنيسة: التاريخ والمذابح والآباء الكهنة والمتنيحون والشفعاء | [features/about-priests-saints.md](features/about-priests-saints.md) |
| محطات تاريخية («قصتنا») | [features/milestones.md](features/milestones.md) |
| الأنشطة والكورالات | [features/activities.md](features/activities.md) |
| الخدمات العامة | [features/public-services.md](features/public-services.md) |
| التنويهات وشريط الإعلان | [features/alerts-and-banner.md](features/alerts-and-banner.md) |
| صفحات التفاصيل لكل عنصر | [features/item-detail-pages.md](features/item-detail-pages.md) |
| الأقسام المخصصة `/section/<slug>` | [features/custom-sections.md](features/custom-sections.md) |
| الصفحات المخصصة `/page/<slug>` (مثل صفحة التبرعات) | [features/custom-pages.md](features/custom-pages.md) |
| نموذج المراسلة وأنواع الرسائل والحجز وصندوق المجهول | [features/contact-form-and-inbox.md](features/contact-form-and-inbox.md) |
| الخريطة والاتجاهات | [features/map-and-directions.md](features/map-and-directions.md) |
| الصور والوسائط | [features/images-and-media.md](features/images-and-media.md) |
| المساعد الذكي «اسأل الكنيسة» `/ask` | [features/assistant.md](features/assistant.md) |
| لوحة التحكم `/admin` (الدخول، الصلاحيات، كل الشاشات) | [features/admin-dashboard.md](features/admin-dashboard.md) |
| تشغيل وإيقاف الأقسام | [features/feature-toggles.md](features/feature-toggles.md) |
| عناوين الصفحات وتذييل الموقع | [features/page-headers-and-footer.md](features/page-headers-and-footer.md) |
| تقارير الأخطاء (Sentry) والخصوصية | [features/error-reporting-sentry.md](features/error-reporting-sentry.md) |
| محركات البحث (SEO) | [features/seo.md](features/seo.md) |
| اللغتان وحفظ اختيار اللغة | [features/localization.md](features/localization.md) |
| تطبيق الويب (PWA) والتخزين المؤقت وخطوط الأيقونات | [features/pwa-and-caching.md](features/pwa-and-caching.md) |
| سهولة الوصول | [features/accessibility.md](features/accessibility.md) |
| تطبيق Android | [features/android-app.md](features/android-app.md) |
| البنية العامة | [architecture.md](architecture.md) |
| التشغيل والنشر والمشاكل الشائعة | [operations.md](operations.md) |

## العلاقة مع «بنك الذاكرة»

- [`docs/memory-bank/`](../docs/memory-bank/00-README.md) بالإنجليزية: الذاكرة الطويلة للمشروع لوكلاء البرمجة،
  بتفاصيل أكثر، وفيه **قرارات التصميم (ADR)** وتاريخ كل PR والمهام المفتوحة
  ([11-open-tasks.md](../docs/memory-bank/11-open-tasks.md)).
- هذا المجلد هو **دليل الاستخدام** بالعربية. عند أي اختلاف: **الكود هو المرجع**، ثم يُصحَّح التوثيق.

## قاعدة التحديث

أي PR يضيف ميزة أو يغيّرها أو يحذفها، أو يغيّر شاشة أو مفتاحًا في `/admin`، أو يغيّر طريقة النشر والتشغيل،
**يحدّث الملف المناسب هنا في نفس الـ PR** (مع بنك الذاكرة). التوثيق القديم يُعامل كخطأ برمجي (ADR-035).

آخر مراجعة شاملة: 4 نوفمبر 2026 على الكود في `main` (بعد PR #24، الكوميت `d60261d`).
