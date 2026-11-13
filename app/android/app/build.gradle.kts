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
        // T-178 (platform-channels §4a): the Google Cloud project linked to
        // Play Integrity. Not a secret; set it with -Pzaghlol.playIntegrityCloudProjectNumber=
        // or in gradle.properties for store builds. 0 (unset) makes attestation
        // fail closed with ATTEST_UNAVAILABLE without calling Google.
        val integrityProject = (findProperty("zaghlol.playIntegrityCloudProjectNumber") as String?)
            ?.trim()?.takeIf { it.matches(Regex("[0-9]{1,19}")) }?.toLongOrNull() ?: 0L
        buildConfigField("long", "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "${integrityProject}L")
    }

    buildFeatures {
        // AGP 9 disables resValue by default; used for the per-flavor app_name.
        resValues = true
        // T-178: the Play Integrity cloud project number (BuildConfig).
        buildConfig = true
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
    // T-178: the shared restore-binding vectors, read in place.
    systemProperty("zaghlol.bindingVectors", rootProject.file("../../backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json").absolutePath)
    systemProperty("zaghlol.guardSources", file("src/main/kotlin/app/zaghlol/platform/guard").absolutePath)
    inputs.dir(guardFixtures).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("guardFixtures")
}

dependencies {
    // T-041: the ingestion worker (expedited WorkManager work, architecture
    // section 7) runs in every flavour (notifications, T-043, need it in
    // *NoSms too). 2.12.0 is stable (2026-09-23), minSdk 24 <= 26. Brings
    // androidx.startup and kotlinx-coroutines-android. Its exported
    // DiagnosticsReceiver is removed in src/main/AndroidManifest.xml.
    implementation("androidx.work:work-runtime:2.12.0")
    // T-103: the unlock prompt (DeviceSecurityHost.authenticate), replacing local_auth.
    implementation("androidx.biometric:biometric:1.1.0")
    // T-178: Play Integrity standard request (platform-channels §4a). 1.6.0 is
    // the latest on Google Maven (2025-11); minSdk 23 <= 26. Adds no permission.
    implementation("com.google.android.play:integrity:1.6.0")
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
