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
        applicationId = "com.asafrachurch.church_portal"
        // sentry_flutter 10 declares minSdk 26 (Android 8.0); Flutter's default is 24.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
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
            if (!storeFilePath.isNullOrBlank() && !keyAliasValue.isNullOrBlank() && !keyPasswordValue.isNullOrBlank() && !storePasswordValue.isNullOrBlank()) {
                val resolvedStoreFile = File(storeFilePath).let { if (it.isAbsolute) it else rootProject.file(storeFilePath) }
                if (resolvedStoreFile.exists()) {
                    storeFile = resolvedStoreFile
                    storePassword = storePasswordValue
                    keyAlias = keyAliasValue
                    keyPassword = keyPasswordValue
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingConfigs.findByName("release")?.storeFile != null) {
                signingConfigs.getByName("release")
            } else {
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
