#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cache=/var/cache/kobuild-android
docs=/usr/share/doc/kobuild
sources=/usr/src/kobuild/android
mkdir -p "$cache" "$docs/qt-licenses" "$sources" "$ANDROID_NDK_ROOT" "$QT_HOST_PATH/lib"
temporary=''
archive=''
cleanup() {
    if [[ -n "$temporary" ]]; then rm -rf "$temporary"; fi
    if [[ -n "$archive" ]]; then rm -f "$archive.partial"; fi
}
trap cleanup EXIT
# Record the installed variant, not the AMD64 host inputs from the shared manifest.
jq --slurpfile native manifest.json --arg tools "$KOBUILD_ANDROID_BUILD_TOOLS" '
    .build_tools = $tools |
    .sdk_packages |= map(if startswith("build-tools;") then "build-tools;" + $tools else . end) |
    .qt_archives = ([ $native[0].archives[] | select(.kind == "qt-host") |
        {name:.file, url, sha256, kind:"qt", destination:"QT_HOST_PATH"} +
        (if .subdirectory then {subdirectory} else {} end)] +
        [.qt_archives[] | select(.kind == "source" or .destination == "QT_ANDROID_ARM64_PATH")])
    ' ../manifest.json > "$docs/android-manifest.json"
cp manifest.json "$docs/android-arm64-manifest.json"

download() {
    local name=$1 url=$2 hash=$3
    archive="$cache/$name"
    if [[ ! -f "$archive" ]] || ! echo "$hash  $archive" | sha256sum -c --status; then
        echo "Downloading $name"
        curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 --max-time 600 \
            --output "$archive.partial" "$url"
        echo "$hash  $archive.partial" | sha256sum -c -
        mv "$archive.partial" "$archive"
    fi
}

while IFS=$'\t' read -r name url hash kind subdirectory; do
    download "$name" "$url" "$hash"
    case "$kind" in
        ndk) tar -xJf "$archive" --strip-components=1 -C "$ANDROID_NDK_ROOT" ;;
        sdk) tar -xJf "$archive" --strip-components=1 -C "$ANDROID_HOME" \
            "android-sdk/build-tools/$KOBUILD_ANDROID_BUILD_TOOLS" android-sdk/platform-tools ;;
        qt-host) 7z x -y -bso0 -o"$QT_HOST_PATH/${subdirectory:-.}" "$archive" ;;
    esac
done < <(jq -r '.archives[] | [.file,.url,.sha256,.kind,(.subdirectory // "")] | @tsv' manifest.json)

# Target Qt libraries and their source archives are shared with the AMD64 SDK.
while IFS=$'\t' read -r name url hash kind; do
    download "$name" "$url" "$hash"
    if [[ "$kind" == source ]]; then
        cp "$archive" "$sources/$name"
        if [[ "$name" == qtbase-* ]]; then
            tar -xJf "$archive" --strip-components=1 -C "$docs/qt-licenses" LICENSES
        fi
    else
        7z x -y -bso0 -o"$QT_ANDROID_ARM64_PATH" "$archive"
    fi
done < <(jq -r '.qt_archives[] | select(.kind == "source" or .destination == "QT_ANDROID_ARM64_PATH") | [.name,.url,.sha256,.kind] | @tsv' ../manifest.json)

IFS=$'\t' read -r name url hash < <(jq -r '.command_line_tools | [.name,.url,.sha256] | @tsv' ../manifest.json)
download "$name" "$url" "$hash"
temporary=$(mktemp -d)
unzip -q "$archive" -d "$temporary"
mkdir -p "$ANDROID_HOME/cmdline-tools"
mv "$temporary/cmdline-tools" "$ANDROID_HOME/cmdline-tools/pinned"
for kit in "$QT_HOST_PATH" "$QT_ANDROID_ARM64_PATH"; do
    printf '[Paths]\nPrefix=..\n' > "$kit/bin/qt.conf"
done
sdkmanager="$ANDROID_HOME/cmdline-tools/pinned/bin/sdkmanager"
# yes exits with SIGPIPE after sdkmanager closes stdin. Check sdkmanager's status.
set +o pipefail
yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" 'platforms;android-36'
set -o pipefail
# Write legacy package metadata during SDK production, while the SDK is writable.
"$sdkmanager" --sdk_root="$ANDROID_HOME" --list_installed > "$docs/android-packages.txt"
test -s "$ANDROID_HOME/platform-tools/package.xml"
test -s "$ANDROID_HOME/build-tools/$KOBUILD_ANDROID_BUILD_TOOLS/package.xml"
