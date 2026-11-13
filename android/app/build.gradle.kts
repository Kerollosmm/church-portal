import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// An env var that is set but empty (the PR build passes blank secrets) must fall through to the next source.
fun envOrNull(name: String): String? = System.getenv(name)?.takeUnless { it.isBlank() }

val keyAliasValue = envOrNull("ANDROID_KEY_ALIAS")
    ?: envOrNull("KEY_ALIAS")
    ?: keystoreProperties.getProperty("keyAlias")
    ?: keystoreProperties.getProperty("KEY_ALIAS")
val keyPasswordValue = envOrNull("ANDROID_KEY_PASSWORD")
    ?: envOrNull("KEY_PASSWORD")
    ?: keystoreProperties.getProperty("keyPassword")
    ?: keystoreProperties.getProperty("KEY_PASSWORD")
val storePasswordValue = envOrNull("ANDROID_KEYSTORE_PASSWORD")
    ?: envOrNull("STORE_PASSWORD")
    ?: keystoreProperties.getProperty("storePassword")
    ?: keystoreProperties.getProperty("STORE_PASSWORD")
val storeFilePath = envOrNull("ANDROID_KEYSTORE_PATH")
    ?: envOrNull("STORE_FILE")
    ?: keystoreProperties.getProperty("storeFile")
    ?: keystoreProperties.getProperty("STORE_FILE")

// Tagged releases set this. A missing keystore must fail the build: signing
// with the debug key (a new certificate on every CI machine) cannot update
// an app that was signed with a different key.
val requireReleaseSigning = envOrNull("ANDROID_REQUIRE_RELEASE_SIGNING")
    ?.equals("true", ignoreCase = true) == true

val releaseStoreFile: java.io.File? = storeFilePath?.takeUnless { it.isBlank() }?.let { path ->
    val candidate = File(path).let { if (it.isAbsolute) it else rootProject.file(path) }
    if (candidate.exists()) candidate else null
}

val releaseSigningReady = releaseStoreFile != null &&
    !keyAliasValue.isNullOrBlank() &&
    !keyPasswordValue.isNullOrBlank() &&
    !storePasswordValue.isNullOrBlank()

fun releaseSigningProblems(): List<String> {
    val missing = mutableListOf<String>()
    if (storeFilePath.isNullOrBlank()) missing += "ANDROID_KEYSTORE_PATH"
    else if (releaseStoreFile == null) missing += "keystore file at ANDROID_KEYSTORE_PATH"
    if (storePasswordValue.isNullOrBlank()) missing += "ANDROID_KEYSTORE_PASSWORD"
    if (keyAliasValue.isNullOrBlank()) missing += "ANDROID_KEY_ALIAS"
    if (keyPasswordValue.isNullOrBlank()) missing += "ANDROID_KEY_PASSWORD"
    return missing
}

android {
    namespace = "com.asafrachurch.church_portal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable forever. A different id installs a second app instead of updating.
        applicationId = "com.asafrachurch.church_portal"
        // sentry_flutter 10 declares minSdk 26 (Android 8.0); Flutter's default is 24.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // pubspec `version: x.y.z+N`. `--split-per-abi` then stores
        // arm32 as 1000+N and arm64 as 2000+N. N must rise for each published APK.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Native libraries compressed inside the APK (extracted at install). With minSdk ≥ 23 AGP stores
    // them uncompressed for mmap, which made the sideloaded / in-app-update download ~29 MB (over the
    // 20 MB budget, PR B §12); compressed they are a fraction of that. Costs a little install-time disk.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                storeFile = releaseStoreFile!!
                storePassword = storePasswordValue!!
                keyAlias = keyAliasValue!!
                keyPassword = keyPasswordValue!!
            }
        }
    }

    buildTypes {
        release {
            // A path or a required release must not fall through to the debug
            // keystore. PR and local builds with no keystore configured still
            // use debug so they can compile; those APKs are not published.
            val wantsReleaseKey = requireReleaseSigning || !storeFilePath.isNullOrBlank()
            if (wantsReleaseKey && !releaseSigningReady) {
                throw GradleException(
                    "Release signing is required but incomplete (${releaseSigningProblems().joinToString()}). " +
                        "Refusing to sign with the debug keystore: a different certificate cannot update the installed app."
                )
            }
            signingConfig = if (releaseSigningReady) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Release APK is signed with the debug keystore. Do not publish it: in-place updates will fail.")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
