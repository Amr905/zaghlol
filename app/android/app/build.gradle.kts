plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// T-038: the shared Capture Guard golden cases and configs (T-035), read in
// place by the Kotlin tests, never copied.
val guardFixtures: File = rootProject.file("../../packages/zaghlol_parsing/test/fixtures/guard")

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

    // T-038: the Guard golden runner lives once in src/sharedTest and runs on
    // the JVM (unit tests, JVM regex) and on devices (androidTest, ICU regex).
    // The shared golden directory is packaged into the test APK only (never
    // into the app APK; GuardGoldenInstrumentedTest asserts it).
    sourceSets {
        getByName("test").java.srcDir("src/sharedTest/kotlin")
        getByName("androidTest").java.srcDir("src/sharedTest/kotlin")
        getByName("androidTest").assets.srcDir(guardFixtures)
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

// T-038: JVM unit tests read the golden file in place; the source scan reads
// the Guard sources. The fixture dir is a task input, so a golden change
// re-runs the tests.
tasks.withType<Test>().configureEach {
    systemProperty("zaghlol.guardFixtures", guardFixtures.absolutePath)
    systemProperty("zaghlol.guardSources", file("src/main/kotlin/app/zaghlol/platform/guard").absolutePath)
    inputs.dir(guardFixtures).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("guardFixtures")
}

// T-008 (SPK-01): the SMS ingestion spike lives in src/devSms only (Lead
// decision Q5), so WorkManager is a dependency of that flavour combination
// only; no staging*/prod* artifact contains it. AGP needs combined-flavour
// configurations declared before use.
val devSmsImplementation by configurations.creating

dependencies {
    // T-008: expedited ingestion work (architecture section 7). 2.12.0 is
    // stable (2026-09-23), minSdk 24 <= 26. Brings androidx.startup (the
    // spike's UI-engine hook) and kotlinx-coroutines-android.
    devSmsImplementation("androidx.work:work-runtime:2.12.0")
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
