# T-190: R8 keep rules for the release build. The Flutter Gradle plugin adds this
# file automatically to the release build type (with proguard-android-optimize.txt
# and Flutter's own rules); build.gradle.kts also turns minify and resource
# shrinking on explicitly. Each rule says what would break without it.
# Most libraries ship consumer rules; the ones below are belt and braces for the
# parts that are reached by name or from native code, which R8 cannot see.

# --- Pigeon (platform channels) ---------------------------------------------
# Generated *.g.kt code is plain Kotlin (no reflection): channels are looked up by
# string name and the codecs are hand-written, so nothing needs keeping. Errors are
# code-only (the *ApiError classes carry an explicit code; the generic path that
# would use the class name is never taken), so renaming classes changes nothing
# the Dart side sees.

# --- Tesseract (Tesseract4Android 4.9.0, JNI) --------------------------------
# libtesseract.so calls back into Java by method and field name (nativeData,
# progress callback, ProgressValues) and the Java side declares the natives.
-keep class cz.adaptech.tesseract4android.** { *; }
-keep class com.googlecode.tesseract.android.** { *; }
-keepclasseswithmembernames class * { native <methods>; }

# --- ML Kit text recognition (bundled Latin model) ---------------------------
# ML Kit loads its components through a registrar listed in the manifest
# (ComponentDiscoveryService) and reads its model files by name; its AARs carry
# consumer rules, repeated here for the component registrars and the JNI glue.
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.mlkit.common.internal.MlKitComponentDiscoveryService { *; }
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# --- Glance home-screen widget (SafeToSpendWidget) ---------------------------
# Receivers and widgets are instantiated by the system from the manifest; action
# callbacks are instantiated by class name from a PendingIntent extra.
-keep class * extends androidx.glance.appwidget.GlanceAppWidgetReceiver { <init>(...); }
-keep class * extends androidx.glance.appwidget.GlanceAppWidget { <init>(...); }
-keep class * implements androidx.glance.appwidget.action.ActionCallback { <init>(...); }
-keep class * extends androidx.glance.appwidget.action.ActionCallback { <init>(...); }

# --- WorkManager (IngestionWorker) -------------------------------------------
# Workers are created through reflection from their class name stored in the
# work spec.
-keep class * extends androidx.work.ListenableWorker { <init>(android.content.Context, androidx.work.WorkerParameters); }

# --- in_app_purchase (Play Billing) ------------------------------------------
# The Flutter plugin is kept by Flutter's rule; Billing's AIDL/Parcelable classes
# are read by the Play Store service by name.
-keep class com.android.billingclient.** { *; }
-keep class com.android.vending.billing.** { *; }
-dontwarn com.android.billingclient.**

# --- Play Integrity ----------------------------------------------------------
-keep class com.google.android.play.core.integrity.** { *; }
-dontwarn com.google.android.play.core.integrity.**

# --- Rive --------------------------------------------------------------------
# rive 0.14 renders through rive_native (C++ via Dart FFI, no Java reflection).
# Kept in case a Java runtime shows up as a transitive dependency.
-keep class app.rive.** { *; }
-keep class com.rive.** { *; }
-dontwarn app.rive.**

# --- Manifest components -----------------------------------------------------
# aapt2 generates keep rules for every class named in the manifest (receivers,
# services, activities); the SMS receiver and notification listener rely on it.
