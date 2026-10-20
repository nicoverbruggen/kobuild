# Qt's official Android libraries and matching Linux host tools. The NDK's
# Linux compiler binaries require an AMD64 container, including on ARM64 hosts.
FROM docker.io/library/ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
ARG DEBIAN_FRONTEND=noninteractive
RUN test "$(dpkg --print-architecture)" = amd64 && \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake curl git libegl1 libfontconfig1 libglib2.0-0t64 \
        libgl1 libopengl0 libxkbcommon0 make ninja-build openjdk-21-jdk-headless \
        p7zip-full patch perl pkg-config python3 unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_ROOT=/opt/android-sdk/ndk/27.2.12479018 \
    QT_HOST_PATH=/opt/Qt/6.11.3/gcc_64 \
    QT_ANDROID_ARM64_PATH=/opt/Qt/6.11.3/android_arm64_v8a \
    LC_ALL=C.UTF-8
ENV PATH=/opt/Qt/6.11.3/android_arm64_v8a/bin:/opt/android-sdk/cmdline-tools/pinned/bin:/opt/android-sdk/platform-tools:/usr/lib/jvm/java-21-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY android/manifest.json android/install.py /usr/local/lib/kobuild/
RUN --mount=type=cache,target=/var/cache/kobuild-android,sharing=locked \
    python3 /usr/local/lib/kobuild/install.py
COPY LICENSE NOTICE /usr/share/doc/kobuild/
COPY android/ICU-LICENSE.txt /usr/share/doc/kobuild/icu-LICENSE.txt
COPY android/check.py /usr/local/lib/kobuild/check-android.py
COPY tools/check-sdk.py /usr/local/bin/kobuild-check
ENV KOBUILD_TARGET=android KOBUILD_ANDROID_BUILD_TOOLS=36.0.0
# The offline check compiles Qt code and checks Android ELF alignment. APK
# packaging runs separately with network access for Gradle's dependencies.
RUN python3 /usr/local/bin/kobuild-check
WORKDIR /work
CMD ["/bin/bash"]
