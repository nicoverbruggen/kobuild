# kobuild

SDK containers for Kobo and Android. Qt5 targets Kobo firmware 4.x; Qt6 targets firmware 5.x/6.x. Android builds standalone ARM64 APKs. Application dependencies and patches stay in the application repository.

```sh
./build.sh qt5
./build.sh qt6
./build.sh android
```

Images are tagged `localhost/kobuild:qt5`, `localhost/kobuild:qt6` and `localhost/kobuild:android`. Docker is used when installed; set `CONTAINER_ENGINE=podman` to select Podman. Builds use two compiler jobs by default; set `JOBS` to change it. Linux AMD64 and ARM64 hosts both produce ARM32 Kobo binaries. Android builds select the native host architecture. Set `ANDROID_HOST_ARCH=amd64` or `ANDROID_HOST_ARCH=arm64` to select it explicitly, including when using a remote container engine. Emulation is required only when selecting another host architecture.

To configure and compile a CMake project:

```sh
docker run --rm -v "$PWD:/work" -w /work localhost/kobuild:qt6 \
    sh -c 'cmake -S . -B build/qt6 -G Ninja && cmake --build build/qt6 --parallel 2'
```

GitHub Actions builds SDKs whose platform folders changed. Releases compare against the last successful release, so a cancelled release does not hide pending changes. Each SDK publishes independently after its own checks pass. A tag such as `v1.0.0` publishes `ghcr.io/<owner>/<repo>:qt6-v1.0.0` when Qt6 changed; unchanged SDK images keep their existing tags. Stable releases also update the selected SDK's alias. Beta tags publish versioned images only. Use the manual workflow's target selector for an explicit rebuild, including changes to shared files outside the platform folders. Select a release tag to publish that rebuild. Publishing uses `GITHUB_TOKEN` with package write access.

## Android

The image includes Qt 6.11.3 Core, Gui, Widgets, Network and Sensors, matching Linux Qt host tools, JDK 21, Android API 36 and NDK 27.2.12479018. Both host architectures target Android 9 and later with the `arm64-v8a` ABI. There is no emulator or x86_64 Android target kit.

AMD64 uses Google's NDK and build-tools 36.0.0. ARM64 uses the checksum-pinned [NDK](https://github.com/HomuHomu833/android-ndk-custom) and [SDK](https://github.com/HomuHomu833/android-sdk-custom) community rebuilds recorded in `android/arm64/manifest.json`, with build-tools 36.1.0. The compiler reports LLVM base `r522817c`; its source revision is recorded in that manifest. These are rebuilt host tools, not official Google ARM64 Linux downloads. Qt host and Android libraries use official Qt binary archives; application builds never compile Qt.

`android/manifest.json` records the Qt binary and source archives with SHA-256 checksums, the command-line tools checksum and the SDK package selections. The installer checks every pinned archive before extraction. SDK package notices remain inside `/opt/android-sdk`; the installed package inventory is `/usr/share/doc/kobuild/android-packages.txt`. Building installs the selected SDK packages and accepts their Android SDK licenses. Review the [SDK terms](https://developer.android.com/studio#terms-and-conditions) before building or redistributing the image.

For an application with CMake Android presets, configure and build inside the image:

```sh
docker run --rm -v "$PWD:/work" -w /work/platforms/android \
    -e GRADLE_USER_HOME=/work/build/gradle \
    localhost/kobuild:android bash -euc \
    'cmake --preset android -DQT_ANDROID_SDK_BUILD_TOOLS_REVISION="$KOBUILD_ANDROID_BUILD_TOOLS"; cmake --build --preset android'
```

The image sets `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_NDK_ROOT`, `QT_HOST_PATH` and `QT_ANDROID_ARM64_PATH`. Application build outputs stay in the mounted checkout. Docker runs as root by default; Linux users can pass `--user "$(id -u):$(id -g)" -e HOME=/tmp` to keep output ownership. Mount a writable Gradle cache separately when reusing downloads. The first APK build needs network access for Gradle and application dependencies.

Use `KOBUILD_ANDROID_BUILD_TOOLS` in application presets or let Qt select the installed version. Use separate application output directories for different host SDKs. When changing SDK versions, regenerate the APK directory as well as the CMake configuration; Qt can retain an older build-tools revision in generated Gradle properties.

The ARM64 recipe is `android/Dockerfile.arm64`. Its installer and checks use Bash, jq, CMake and presets, without Python. The image sets `GRADLE_OPTS` to select its native `aapt2` and disable persistent Gradle daemons. Preserve these options when adding Gradle options; AGP otherwise downloads an AMD64 `aapt2` from Maven. SDK package metadata is generated during image production, so applications can run as an unprivileged user without modifying the SDK.

The SDK check compiles and links a Qt Widgets app with Network, Sensors, moc and rcc. It verifies the ARM64 output, 16 KiB ELF alignment and source archive checksums without running Android code. The ARM64 check also verifies that the compiler, Qt and SDK executables are ARM64. `./build.sh android` and CI also package a disposable APK, check its metadata and alignment, and sign and verify it with a temporary test key. That packaging check needs network access. Local Gradle downloads stay in the ignored `build/android-gradle-amd64/` and `build/android-gradle-arm64/` caches; CI saves separate caches for both architectures. Test projects, keys and containers are removed when checks finish. Release signing keys belong to the application's release workflow and are never inputs to this image.

CI builds Android on native AMD64 and ARM64 runners and publishes both into the same `android` and versioned `android-vVERSION` tags after both checks pass. Docker selects the matching host image when pulling. The image host architecture is separate from the Android `arm64-v8a` target ABI.

The Qt6 image includes its prepared Qt source and build scripts in `/usr/src/kobuild/qt6-source.tar.xz`. The Android image includes its matching Qt Base and Qt Sensors source archives in `/usr/src/kobuild/android/`. These cover Qt, not all system packages. Exact source provenance for all components inherited from NickelTC in the Qt5 image remains unverified.

Scripts use [MIT](LICENSE). See [NOTICE](NOTICE) and [Qt patch notices](qt6/source/NOTICE) for third-party terms and sources.
