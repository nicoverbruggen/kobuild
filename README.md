# kobuild

SDK containers for Kobo and Android. Qt5 targets Kobo firmware 4.x; Qt6 targets firmware 5.x/6.x. Android builds standalone ARM64 APKs. Application dependencies and patches stay in the application repository.

```sh
./build.sh qt5
./build.sh qt6
./build.sh android
```

Images are tagged `localhost/kobuild:qt5`, `localhost/kobuild:qt6` and `localhost/kobuild:android`. Docker is used when installed; set `CONTAINER_ENGINE=podman` to select Podman. Builds use two compiler jobs by default; set `JOBS` to change it. Linux AMD64 and ARM64 hosts both produce ARM32 Kobo binaries. The Android image requires Linux AMD64; the build script selects that platform on ARM64 hosts, which need AMD64 container emulation.

To configure and compile a CMake project:

```sh
docker run --rm -v "$PWD:/work" -w /work localhost/kobuild:qt6 \
    sh -c 'cmake -S . -B build/qt6 -G Ninja && cmake --build build/qt6 --parallel 2'
```

GitHub Actions builds SDKs whose platform folders changed. Releases compare against the last successful release, so a cancelled release does not hide pending changes. Each SDK publishes independently after its own checks pass. A tag such as `v1.0.0` publishes `ghcr.io/<owner>/<repo>:qt6-v1.0.0` when Qt6 changed; unchanged SDK images keep their existing tags. Stable releases also update the selected SDK's alias. Beta tags publish versioned images only. Use the manual workflow's target selector for an explicit rebuild, including changes to shared files outside the platform folders. Select a release tag to publish that rebuild. Publishing uses `GITHUB_TOKEN` with package write access.

## Android

The image includes Qt 6.11.3 Core, Gui, Widgets, Network and Sensors, matching Linux Qt host tools, JDK 21, Android API 36, build tools 36.0.0 and NDK 27.2.12479018. It targets Android 9 and later with the `arm64-v8a` ABI. It does not include an emulator or an x86_64 Android kit. Google's Linux NDK tools require an AMD64 host.

`android/manifest.json` records the Qt binary and source archives with SHA-256 checksums, the command-line tools checksum and the SDK package selections. The installer checks every pinned archive before extraction. SDK package notices remain inside `/opt/android-sdk`; the installed package inventory is `/usr/share/doc/kobuild/android-packages.txt`. Building installs the selected SDK packages and accepts their Android SDK licenses. Review the [SDK terms](https://developer.android.com/studio#terms-and-conditions) before building or redistributing the image.

From a public Kobalt checkout, build a debug APK with:

```sh
docker run --rm --platform linux/amd64 -v "$PWD:/work" -w /work \
    -e GRADLE_USER_HOME=/work/.cache/gradle \
    localhost/kobuild:android python3 android/build.py --jobs 2
```

The image sets `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_NDK_ROOT`, `QT_HOST_PATH` and `QT_ANDROID_ARM64_PATH`. Application build outputs stay in the mounted checkout. Docker runs as root by default; Linux users can pass `--user "$(id -u):$(id -g)" -e HOME=/tmp` to keep output ownership. Mount a writable Gradle cache separately when reusing downloads. The first APK build needs network access for Gradle and application dependencies.

The SDK check compiles and links a Qt Widgets app with Network, Sensors, moc and rcc. It verifies the ARM64 output, 16 KiB ELF alignment and source archive checksums without running Android code. `./build.sh android` and CI also package a disposable APK, check its metadata and alignment, and sign and verify it with a temporary test key. That packaging check needs network access. Gradle downloads stay in the ignored `build/android-gradle/` cache; CI saves that cache between runs. Release signing keys belong to the application's release workflow and are never inputs to this image.

The Qt6 image includes its prepared Qt source and build scripts in `/usr/src/kobuild/qt6-source.tar.xz`. The Android image includes its matching Qt Base and Qt Sensors source archives in `/usr/src/kobuild/android/`. These cover Qt, not all system packages. Exact source provenance for all components inherited from NickelTC in the Qt5 image remains unverified.

Scripts use [MIT](LICENSE). See [NOTICE](NOTICE) and [Qt patch notices](qt6/source/NOTICE) for third-party terms and sources.
