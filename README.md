# kobuild

Kobalt build tooling. This repository builds SDK images for Kobo, Kindle, Android and the Linux desktop. The Qt5 and Qt6 SDKs target Kobo firmware 4.x and 5.x/6.x, respectively. The Android SDK builds standalone ARM64 APKs. The Linux SDK builds and tests desktop clients. Application dependencies and patches stay in the application repository.

## Build locally

```sh
./build.sh qt5
./build.sh qt6
./build.sh android
./build.sh linux
./build.sh kindle
```

Local builds use `localhost/kobuild:<target>` tags. The build script prefers Docker when installed. Set `CONTAINER_ENGINE=podman` to select Podman. Builds use two compiler jobs by default. Set `JOBS` to change it.

## Kobo

Linux AMD64 and ARM64 hosts both produce ARM32 Kobo binaries. The Qt5 SDK check verifies that the compiler uses the NickelTC sysroot's glibc 2.19 headers, which match Kobo firmware 4.x.

To configure and compile a CMake project:

```sh
docker run --rm -v "$PWD:/work" -w /work localhost/kobuild:qt6 \
    sh -c 'cmake -S . -B build/qt6 -G Ninja && cmake --build build/qt6 --parallel 2'
```

## Releases

GitHub Actions builds SDKs whose recipe folders changed. Tagged releases compare against the last successful release. Each SDK publishes after its own checks pass. A release such as `v1.0.0` names every SDK, for example `ghcr.io/nicoverbruggen/kobuild:qt6-v1.0.0`. Unchanged SDKs keep their previous image digest. Stable releases also update aliases such as `qt6`. Prereleases publish versioned tags only.

Use the manual target selector to rebuild an SDK, including after changes to shared files outside the recipe folders. Select a release tag to publish that rebuild. Publishing uses `GITHUB_TOKEN` with package write access.

## Android

The image includes Qt 6.11.3 Core, Gui, Widgets, Network and Sensors, matching Linux Qt host tools, JDK 21, Android API 36 and NDK 27.2.12479018. Both host architectures target Android 9 and later with the `arm64-v8a` ABI. There is no emulator or x86_64 Android target kit.

Local builds select the native host architecture by default. Set `ANDROID_HOST_ARCH=amd64` or `ANDROID_HOST_ARCH=arm64` to select it explicitly, including when using a remote container engine. A non-native host image needs emulation.

AMD64 uses Google's NDK and build-tools 36.0.0. ARM64 uses the checksum-pinned [NDK](https://github.com/HomuHomu833/android-ndk-custom) and [SDK](https://github.com/HomuHomu833/android-sdk-custom) community rebuilds recorded in `android/arm64/manifest.json`, with build-tools 36.1.0. The compiler reports LLVM base `r522817c`; its source revision is recorded in that manifest. These are rebuilt host tools, not official Google ARM64 Linux downloads. Qt host and Android libraries use official Qt binary archives; application builds never compile Qt.

`android/manifest.json` records the Qt binary and source archives with SHA-256 checksums, the command-line tools checksum and the SDK package selections. The installer checks every pinned archive before extraction. SDK package notices remain inside `/opt/android-sdk`; the installed package inventory is `/usr/share/doc/kobuild/android-packages.txt`. Building installs the selected SDK packages and accepts their Android SDK licenses. Review the [SDK terms](https://developer.android.com/studio#terms-and-conditions) before building or redistributing the image.

For an application with CMake Android presets, configure and build inside the image:

```sh
docker run --rm -v "$PWD:/work" -w /work/platforms/android \
    -e GRADLE_USER_HOME=/work/build/gradle \
    localhost/kobuild:android bash -euc \
    'cmake --preset android -DQT_ANDROID_SDK_BUILD_TOOLS_REVISION="$KOBUILD_ANDROID_BUILD_TOOLS"; cmake --build --preset android'
```

The image sets `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_NDK_ROOT`, `QT_HOST_PATH` and `QT_ANDROID_ARM64_PATH`. Application build outputs stay in the mounted checkout. Docker runs as root by default; Linux users can pass `--user "$(id -u):$(id -g)" -e HOME=/tmp` to keep output ownership. Mount a writable Gradle cache separately when reusing downloads. The image bundles the checksum-pinned Gradle distribution selected by Qt. Qt's wrapper uses its local archive in `/opt/gradle`, including with an empty mounted Gradle cache. The first APK build still needs network access for Android Gradle Plugin and application dependencies.

Use `KOBUILD_ANDROID_BUILD_TOOLS` in application presets or let Qt select the installed version. Use separate application output directories for different host SDKs. When changing SDK versions, regenerate the APK directory as well as the CMake configuration; Qt can retain an older build-tools revision in generated Gradle properties.

The ARM64 recipe is `android/Dockerfile.arm64`. Its installer and checks use Bash, jq, CMake and presets, without Python. The image sets `GRADLE_OPTS` to select its native `aapt2` and disable persistent Gradle daemons. Preserve these options when adding Gradle options; AGP otherwise downloads an AMD64 `aapt2` from Maven. SDK package metadata is generated during image production, so applications can run as an unprivileged user without modifying the SDK.

The SDK check starts the bundled Gradle through Qt's wrapper with a fresh cache, then compiles and links a Qt Widgets app with Network, Sensors, moc and rcc. It verifies the ARM64 output, 16 KiB ELF alignment and source archive checksums without running Android code. The ARM64 check also verifies that the compiler, Qt and SDK executables are ARM64. `./build.sh android` and CI also package a disposable APK, check its metadata and alignment, and sign and verify it with a temporary test key. That packaging check needs network access. Local Gradle downloads stay in the ignored `build/android-gradle-amd64/` and `build/android-gradle-arm64/` caches; CI saves separate caches for both architectures. Test projects, keys and containers are removed when checks finish. Release signing keys belong to the application's release workflow and are never inputs to this image.

CI builds Android on native AMD64 and ARM64 runners and publishes both into the same `android` and versioned `android-vVERSION` tags after both checks pass. Docker selects the matching host image when pulling. The image host architecture is separate from the Android `arm64-v8a` target ABI.

## Linux

The image includes Qt 6.11.3 for the Linux desktop with Core, Gui, Widgets, Network, Sql, Test, the private Gui headers and Qt's bundled libpng, plus GCC, CMake, Ninja and the OpenGL, EGL, xkbcommon and fontconfig development packages that Qt's CMake packages require. It does not include Qt Sensors. AMD64 and ARM64 hosts use the same recipe, `linux/Dockerfile`, and install the official Qt binary archives of their own architecture, the same ones the Android image uses as its host Qt. `linux/manifest.json` records them with SHA-256 checksums; the installer checks every archive before extraction. Qt is installed at `/opt/Qt/6.11.3/linux` on both hosts, and the image sets `QT_PATH` and `CMAKE_PREFIX_PATH` to it, so `find_package(Qt6)` needs no options.

```sh
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/work" -w /work localhost/kobuild:linux \
    sh -c 'cmake -S . -B build/linux -G Ninja && cmake --build build/linux && QT_QPA_PLATFORM=offscreen ctest --test-dir build/linux'
```

The SDK check builds, links and runs a Qt Widgets program headless with the offscreen platform. It checks simulated input, SQLite, resources and libpng, and the checksums of the Qt source archive in `/usr/src/kobuild/linux/`. The installer and check use Bash, jq and CMake, without Python.

## Kindle

The `kindle` target matches Kobalt's `kindle` CMake preset. It uses KOReader's `arm-kindlehf-linux-gnueabihf` toolchain and targets ARMv7 hard float with glibc 2.20. The SDK image runs on Linux AMD64. ARM64 build hosts need AMD64 container emulation.

The SDK includes Qt 6.8.3 in `/sdk/qt`, matching Qt host tools in `/sdk/qt-host`, OpenSSL in `/sdk/openssl`, zlib in `/sdk/runtime` and FBInk in `/sdk/fbink`. The SDK check builds and links a Qt program, checks the Qt plugins, and verifies the ARM ABI and glibc symbol versions.

For shared builds, use a published `ghcr.io/nicoverbruggen/kobuild:kindle-vVERSION` image and pin its digest. `./build.sh kindle` builds the local test image.

The GCC 14.4.0 runtime libraries (`libstdc++.so.6`, `libgcc_s.so.1` and `libatomic.so.1`) come from the [KOReader toolchain release](https://github.com/koreader/koxtoolchain/releases/tag/2026.08) pinned in `kindle/manifest.json`. The SDK includes GNU GCC sources, the KOReader build recipe, the exact crosstool-NG revision with its GCC patches, the embedded build configuration, and the GPL and GCC Runtime Library Exception texts. `kindle/gcc-runtime-sources.json` pins these source archives and binds them to the compiler archive checksum. The remaining Kindle recipe inputs and patches are in `/usr/src/kobuild/kindle`.

To export the GCC runtime source bundle, set `SDK_IMAGE` to the SDK image that supplied the libraries and run:

```sh
docker run --rm --platform linux/amd64 --entrypoint tar "$SDK_IMAGE" \
    -C /usr/src/kobuild/kindle -cf - gcc-runtime > kindle-gcc-runtime-sources.tar
```

## Sources and licenses

The Qt6 image includes its prepared Qt source and build scripts in `/usr/src/kobuild/qt6-source.tar.xz`. The Android image includes its matching Qt Base and Qt Sensors source archives in `/usr/src/kobuild/android/`. The exact source revisions of some components inherited from NickelTC in the Qt5 image remain unverified.

Scripts use [MIT](LICENSE). See [NOTICE](NOTICE) and [Qt patch notices](qt6/source/NOTICE) for third-party terms and sources.
