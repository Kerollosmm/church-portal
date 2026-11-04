# تطبيق Android

## الحالة الحالية

نفس كود الموقع يُبنى كتطبيق Android، لكنه **غير منشور على Google Play بعد** ولا يوجد بناء Android في CI.

| البند | الحالة |
|---|---|
| المعرّف | `com.asafrachurch.church_portal` |
| الاسم الظاهر | «كنيسة مكسيموس ودوماديوس» مع أيقونة الختم |
| المحتوى، الصفحات، نموذج التواصل، الخريطة (بطاقة بدل الخريطة المضمّنة) | يعمل |
| المساعد الذكي | **لا يعمل بعد**: يحتاج مفتاح توقيع release + تسجيل SHA-256 + Play Integrity في App Check |
| التوقيع | release يُوقَّع حاليًا بمفتاح debug (`android/app/build.gradle.kts`) |
| Sentry | يعمل في إصدارات release (Sentry Android SDK)، بنفس مفتاح الإيقاف في اللوحة |
| حفظ اختيار اللغة | غير مدعوم (يبدأ بالعربية) |
| iOS | جاهز في الكود لكن غير مسجل في Firebase (`lib/firebase_options.dart` فيه قيم مؤقتة) |

## التحكم من لوحة التحكم

نفس لوحة التحكم ونفس البيانات؛ أي تعديل يظهر في الموقع والتطبيق معًا.

## كيف تعمل تقنيًا

- App Check على Android: `AndroidPlayIntegrityProvider` في release، و `AndroidDebugProvider` في debug
  (`lib/data/app_check_providers.dart`). App Check مفروض على AI Logic فقط، **وليس** على Firestore (حتى لا يتعطل التطبيق
  قبل تسجيل Play Integrity).
- صلاحية `INTERNET` مضافة لإصدارات release.
- البناء اليدوي:
  `flutter build apk --release --dart-define=SENTRY_ENVIRONMENT=production --dart-define=GIT_SHA=$(git rev-parse HEAD) --dart-define=APP_VERSION=1.0.0+1`

## خطوات تشغيل المساعد على Android (للمالك)

1. إنشاء مفتاح رفع: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   وربطه في `signingConfigs.release` (المفتاح وكلمات المرور **خارج git**).
2. نسخ **SHA-256** (`keytool -list -v -keystore upload-keystore.jks -alias upload`، أو مفتاح App Signing من Play Console).
3. Firebase Console ← Project settings ← تطبيق Android ← Add fingerprint.
4. App Check ← Apps ← Android ← **Play Integrity** ← Register (وربط مشروع Cloud في Play Console).
5. لنسخ debug: انسخ رمز debug من logcat وأضفه في App Check ← Manage debug tokens.

## الحدود والمشاكل المعروفة

- لا رفع لرموز Dart/R8 إلى Sentry (التطبيق غير مُعمّى بعد).
- حساب Google Play (25 دولارًا) وصفحة المتجر لم يُنشآ.
