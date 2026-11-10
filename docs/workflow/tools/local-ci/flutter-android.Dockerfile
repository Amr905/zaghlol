# Local-CI Android image, built once on the PO's PC by runner.ps1 on top of the quick Flutter image
# (flutter.Dockerfile), so format/analyze/test steps keep using the small image. Mirrors app-ci.yml:
# Java 17, `flutter build apk`, Gradle unit tests and lint, aapt2 permission checks.
#
# Versions (why):
#  - JDK 17: app/android/app/build.gradle.kts sets JVM 17; AGP 9.1 / Gradle 9.3.1 need 17+. Debian's OpenJDK 17
#    stands in for Temurin 17 (same language level, no extra download to pin).
#  - NDK 28.2.13676358: flutter.ndkVersion in Flutter 3.47.9 (FlutterExtension.kt / gradle_utils.dart).
#  - compileSdk/platform android-36: app/android/app/build.gradle.kts (compileSdk = 36, targetSdk = 36).
#  - build-tools 36.0.0: default of AGP 9.1.0 (settings.gradle.kts); also provides aapt2 and zipalign for the
#    apk-perms check. If AGP wants another version, Gradle downloads it into the SDK on first use (licenses
#    are accepted below), so a mismatch costs time, not a failure.
#  - cmdline-tools 13114758 (Google "latest" at pin time), SHA-256 checked. The hash comes from the nixpkgs
#    package for this exact zip. If the build stops with "FAILED" from sha256sum, Google changed the file or the
#    hash is wrong: take the hash from https://developer.android.com/studio#command-line-tools-only
#    (the page lists SHA-256) and pass --build-arg CMDLINE_TOOLS_SHA256=...
ARG BASE_IMAGE=zaghlol-flutter:3.47.9
FROM ${BASE_IMAGE}
ARG CMDLINE_TOOLS_BUILD=13114758
ARG CMDLINE_TOOLS_SHA256=76df27c232fcc3245f05939e7423d85e1ef3c9e314787d2038fa53729c427a05
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_NDK=28.2.13676358
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(dirname "$(dirname "$(readlink -f "$(which javac)")")")" /opt/java \
 && /opt/java/bin/javac -version
ENV JAVA_HOME=/opt/java \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
RUN curl -fsSL -o /tmp/clt.zip "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" \
 && echo "${CMDLINE_TOOLS_SHA256}  /tmp/clt.zip" | sha256sum -c - \
 && mkdir -p "$ANDROID_HOME/cmdline-tools" /tmp/clt \
 && unzip -q /tmp/clt.zip -d /tmp/clt \
 && mv /tmp/clt/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
 && rm -rf /tmp/clt /tmp/clt.zip
# Licenses first (non-interactive), then the packages. `yes` ends with SIGPIPE, hence the || true on the license step.
RUN (yes | sdkmanager --licenses > /dev/null || true) \
 && sdkmanager --install "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}" "ndk;${ANDROID_NDK}" \
 && sdkmanager --list_installed
RUN flutter config --android-sdk "$ANDROID_HOME" --jdk-dir "$JAVA_HOME" \
 && flutter precache --android \
 && (flutter doctor -v || true)
