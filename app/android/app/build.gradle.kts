plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.zaghlol"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Prod applicationId; dev/staging add a suffix below (deployment.md section 1).
        applicationId = "app.zaghlol"
        // ADR-019: minSdk 26 (Android 8.0), targetSdk 36.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        // AGP 9 disables resValue by default; used for the per-flavor app_name.
        resValues = true
    }

    // Dimension order matters: variants are named <env><Sms|NoSms>, e.g. prodNoSms.
    flavorDimensions += listOf("env", "sms")

    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Zaghlol Dev")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Zaghlol Staging")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Zaghlol")
        }
        // ADR-004: READ_SMS / RECEIVE_SMS live only in src/sms/AndroidManifest.xml.
        create("sms") {
            dimension = "sms"
        }
        create("noSms") {
            dimension = "sms"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
