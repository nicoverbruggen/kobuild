#!/bin/bash
set -euo pipefail
case "${1:-}" in '') apk=OFF ;; --apk) apk=ON ;; *) echo 'Usage: kobuild-check [--apk]' >&2; exit 2 ;; esac
[[ $# -le 1 && $(uname -m) == aarch64 ]]
for tool in cmake ninja make patch perl pkg-config; do
    command -v "$tool" >/dev/null
done
docs=/usr/share/doc/kobuild
tools="$ANDROID_HOME/build-tools/$KOBUILD_ANDROID_BUILD_TOOLS"
llvm="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin"
for binary in "$llvm/clang" "$llvm/ld.lld" "$llvm/llvm-ar" "$llvm/llvm-objcopy" "$llvm/llvm-strip" "$llvm/llvm-readelf" \
    "$QT_HOST_PATH/libexec/moc" "$QT_HOST_PATH/libexec/rcc" "$QT_HOST_PATH/bin/androiddeployqt" \
    "$tools/aapt" "$tools/aapt2" "$tools/aidl" "$tools/dexdump" "$tools/zipalign" \
    "$tools/split-select" "$ANDROID_HOME/platform-tools/adb" "$ANDROID_HOME/platform-tools/fastboot" "$JAVA_HOME/bin/java"; do
    file -L "$binary" | grep -q 'ARM aarch64'
done
[[ $(jq -r .build_tools "$docs/android-arm64-manifest.json") == "$KOBUILD_ANDROID_BUILD_TOOLS" ]]
for notice in LICENSE NOTICE qt-licenses/LGPL-3.0-only.txt icu-LICENSE.txt android-packages.txt; do
    test -s "$docs/$notice"
done
while IFS=$'\t' read -r name hash; do
    echo "$hash  /usr/src/kobuild/android/$name" | sha256sum -c -
done < <(jq -r '.qt_archives[] | select(.kind == "source") | [.name,.sha256] | @tsv' "$docs/android-manifest.json")
grep -qx 'Pkg.Revision = 27.2.12479018' "$ANDROID_NDK_ROOT/source.properties"
test -s "$ANDROID_HOME/platform-tools/package.xml"
test -s "$tools/package.xml"

check_elf() {
    "$llvm/llvm-readelf" -h "$1" | grep -q 'Machine:.*AArch64'
    local alignments
    alignments=$("$llvm/llvm-readelf" -lW "$1" | awk '$1 == "LOAD" {print $NF}')
    [[ -n "$alignments" ]]
    while IFS= read -r alignment; do (( alignment >= 16384 )); done <<< "$alignments"
}
for library in Core Gui Widgets Network Sensors; do
    check_elf "$QT_ANDROID_ARM64_PATH/lib/libQt6${library}_arm64-v8a.so"
done
work=$(mktemp -d /tmp/kobuild-android-check.XXXXXX)
trap 'rm -rf "$work"' EXIT
cp /usr/local/lib/kobuild/arm64/smoke/* "$work/"
cd "$work"
cmake --preset android
cmake --build --preset android --target check
check_elf build/libcheck_arm64-v8a.so
"$llvm/llvm-readelf" -d build/libcheck_arm64-v8a.so > dependencies.txt
for library in Widgets Network Sensors; do grep -q "libQt6${library}_arm64-v8a.so" dependencies.txt; done
if [[ "$apk" == ON ]]; then
    cmake --build --preset android
    package="$work/build/android-build/check.apk"
    "$tools/aapt2" dump badging "$package" > badging.txt
    for expected in "package: name='org.kobuild.check'" "minSdkVersion:'28'" \
        "targetSdkVersion:'36'" "native-code: 'arm64-v8a'"; do
        grep -F "$expected" badging.txt
    done
    unzip -Z1 "$package" | grep -E '^lib/.*\.so$' > libraries.txt
    grep -q 'lib/arm64-v8a/libcheck_arm64-v8a.so' libraries.txt
    while IFS= read -r entry; do
        [[ "$entry" == lib/arm64-v8a/* ]]
        unzip -p "$package" "$entry" > library.so
        check_elf library.so
    done < libraries.txt
    "$tools/zipalign" -c -P 16 4 "$package"
    keytool -genkeypair -noprompt -storetype PKCS12 -keystore key.p12 -alias check \
        -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 1 -dname 'CN=kobuild check'
    "$tools/apksigner" sign --ks key.p12 --ks-type PKCS12 --ks-key-alias check \
        --ks-pass pass:android --key-pass pass:android --v4-signing-enabled false --out signed.apk "$package"
    "$tools/apksigner" verify --verbose signed.apk
    "$tools/zipalign" -c -P 16 4 signed.apk
fi
echo 'ARM64 host tools, Qt code generation, Android link, alignment and distribution checks passed'
if [[ "$apk" == ON ]]; then echo 'APK packaging and test signing passed'; fi
