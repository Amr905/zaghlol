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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

    // T-165: AllowBackup / DataExtractionRules / FullBackupContent are fatal (lint.xml).
    lint {
        lintConfig = file("lint.xml")
        abortOnError = true
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
    // T-159 (ADR-009, CR-02): on-device OCR, versions pinned on purpose.
    // ML Kit Text Recognition v2, Latin, BUNDLED model (no model download).
    // Google ML Kit terms; adds roughly 4 MB per ABI (compressed .so).
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // Tesseract 5.5 JNI wrapper, standard (single-thread) variant. Apache-2.0.
    // The bundled model is tessdata_fast ara (Apache-2.0), see TessdataSpec.
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
    testImplementation("junit:junit:4.13.2")
    // T-060: instrumented tests (Keystore cipher, share store on a device).
    // Versions match what the integration_test plugin already puts on the debug
    // runtime classpath; Gradle's consistent resolution rejects anything else.
    androidTestImplementation("junit:junit:4.12")
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.2")
}

flutter {
    source = "../.."
}
