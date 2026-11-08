# android

## Overview
The `android` component package contains the native Android application harness, Gradle build pipeline, platform channels, and system integration services for the Flutter application. It defines two custom platform channels (`church_portal/device` and `church_portal/installer`) in `MainActivity.kt` that provide hardware and power diagnostics, route users to OEM-specific battery optimization and autostart screens across popular device manufacturers, schedule diagnostic alarms via `AlarmManager`, and safely verify and install sideloaded APK updates using Android's `FileProvider` with cryptographic certificate checks.

## Interface
- **Platform Channels & Native Activities:**
  - `[android/app/src/main/kotlin/com/asafrachurch/church_portal/MainActivity.kt:MainActivity]`: Main activity subclassing `FlutterActivity`, registering method channels on Flutter engine initialization:
    - **Channel `church_portal/device`:**
      - `getDeviceInfo`: Returns map with `manufacturer`, `brand`, `model`, and `sdkInt`.
      - `isIgnoringBatteryOptimizations`: Invokes `PowerManager.isIgnoringBatteryOptimizations(packageName)` to check battery exemption status.
      - `openSettings`: Resolves and fires intents by action and component name, falling back to application details.
      - `getDiagnostics`: Aggregates device telemetry including battery optimization state, exact alarm scheduling capability (`AlarmManager.canScheduleExactAlarms`), and notification permissions (`POST_NOTIFICATIONS` or `NotificationManager.areNotificationsEnabled`).
      - `openOemSettings`: Resolves vendor-specific autostart or power manager activities (Xiaomi, Oppo, Vivo, Huawei, Samsung) via `oemIntentTryLists`.
      - `openAppSettings`: Launches `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` for the app.
      - `scheduleTestAlarm`: Schedules a test alarm via `AlarmManager` (using `setExactAndAllowWhileIdle` when permitted, or `setAndAllowWhileIdle`) targeting `TestAlarmReceiver`.
    - **Channel `church_portal/installer`:**
      - `getCacheDir`: Returns absolute path of application cache directory (`cacheDir.absolutePath`).
      - `supportedAbi`: Returns primary CPU ABI (`Build.SUPPORTED_ABIS.first()`).
      - `canRequestPackageInstalls` / `canRequestInstalls`: Checks unknown app install permission via `PackageManager.canRequestPackageInstalls()`.
      - `openManageUnknownApps` / `openUnknownSourcesSettings`: Opens `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` targeting the app package.
      - `verifyApkSignature` / `apkCertMatches`: Validates that a target APK matches the app package name (`com.asafrachurch.church_portal`) and its signing certificates match installed certificates and optional expected SHA-256 fingerprint.
      - `installApk`: Launches the Android package installer with a `FileProvider` content URI (`${packageName}.updates`).
  - `[android/app/src/main/kotlin/com/asafrachurch/church_portal/MainActivity.kt:TestAlarmReceiver]`: `BroadcastReceiver` receiving the test alarm and dispatching a test notification on the `reminders` notification channel.
- **Build Configuration & Security:**
  - `[android/app/build.gradle.kts]`: Android application Gradle build script with core library desugaring (`desugar_jdk_libs`), Java 17 compatibility, minSdk 26 (Android 8.0), JNI legacy packaging compression (`useLegacyPackaging = true`), ProGuard shrinking/obfuscation, and release keystore environment resolution.
  - `[android/app/src/main/AndroidManifest.xml]`: Declares permissions (`INTERNET`, `RECEIVE_BOOT_COMPLETED`, `REQUEST_INSTALL_PACKAGES`, `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM`, `POST_NOTIFICATIONS`), `FileProvider` definition (`${applicationId}.updates`), and `<queries>` elements for OEM security managers.
- **Subdirectories & Boundaries:**
  - `./app`: Android application module containing Kotlin sources (`src/main/kotlin`), XML resources (`res/`), and Gradle build definitions.
  - `./gradle`: Gradle wrapper configuration and runtime launcher.

## Invariants
- `[android/app/src/main/kotlin/com/asafrachurch/church_portal/MainActivity.kt:verifyApkSignatureInternal]`: Sideloaded APK verification must confirm that the archive package name strictly equals `packageName` (`com.asafrachurch.church_portal`), that archive certificates match installed certificates, and that archive certificate hashes match `expectedCertSha256` if supplied.
- `[android/app/build.gradle.kts:packaging]`: Native `.so` libraries must use legacy compressed packaging (`useLegacyPackaging = true`) to maintain the release APK bundle size within the 20 MB budget.
- `[android/app/src/main/kotlin/com/asafrachurch/church_portal/MainActivity.kt:installApkInternal]`: Sideloaded APK installations must access files exclusively via `FileProvider` authorities (`${packageName}.updates`) mapped to `cacheDir/updates/` (`res/xml/update_paths.xml`).
- `[android/app/src/main/kotlin/com/asafrachurch/church_portal/MainActivity.kt:openOemAction]`: If any vendor-specific autostart or power manager intent cannot be resolved or crashes, the invocation must cleanly fall back to `openAppDetailsSettings()`.

## Side Effects
- Spawns external system activities: launches Android Settings, OEM security apps, and the package installer via `Intent.FLAG_ACTIVITY_NEW_TASK`.
- Accesses disk storage: reads APK metadata and certificates from `cacheDir/updates/`.
- Interacts with system services: interacts with `AlarmManager`, `NotificationManager`, `PowerManager`, and `PackageManager`.
- Emits local test notifications on channel `reminders`.

## Verification
- Run: `flutter build apk`
