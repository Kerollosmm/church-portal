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

val keyAliasValue = System.getenv("KEY_ALIAS")
    ?: keystoreProperties.getProperty("keyAlias")
    ?: keystoreProperties.getProperty("KEY_ALIAS")
val keyPasswordValue = System.getenv("KEY_PASSWORD")
    ?: keystoreProperties.getProperty("keyPassword")
    ?: keystoreProperties.getProperty("KEY_PASSWORD")
val storePasswordValue = System.getenv("STORE_PASSWORD")
    ?: keystoreProperties.getProperty("storePassword")
    ?: keystoreProperties.getProperty("STORE_PASSWORD")
val storeFilePath = System.getenv("STORE_FILE")
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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (storeFilePath != null && keyAliasValue != null && keyPasswordValue != null && storePasswordValue != null) {
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
