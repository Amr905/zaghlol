# Local-CI Flutter image, built once on the PO's PC by runner.ps1 (no official image exists for every
# Flutter release). Mirrors app-ci.yml: same version, and the checkout must match FLUTTER_SHA in app-regen.yml.
FROM debian:bookworm-slim
ARG FLUTTER_VERSION=3.47.9
ARG FLUTTER_SHA=c197ca5199e9ee5661e865596c9c07294dfab51c
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl unzip xz-utils zip ca-certificates libglu1-mesa \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter \
 && test "$(git -C /opt/flutter rev-parse HEAD)" = "$FLUTTER_SHA"
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true
RUN git config --system --add safe.directory '*' \
 && flutter config --no-analytics --no-cli-animations \
 && flutter precache --universal --no-android --no-ios --no-web --no-linux --no-windows --no-macos --no-fuchsia \
 && dart --disable-analytics \
 && flutter --version
