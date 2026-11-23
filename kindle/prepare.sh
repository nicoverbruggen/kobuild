#!/usr/bin/env bash
set -euo pipefail

# This prepares an SDK. Application builds consume it without rebuilding Qt.
sdk=/sdk
recipe=$(cd "$(dirname "$0")" && pwd)
downloads=$sdk/downloads
sources=$sdk/src
jobs=${JOBS:-4}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be positive' >&2; exit 2; }
mkdir -p "$downloads" "$sources" "$sdk/home"
exec 9>"$sdk/prepare.lock"
flock -n 9 || { echo 'The Kindle SDK is already being prepared' >&2; exit 1; }
rm -f "$sdk/ready.txt"

fetch() {
    local name=$1 url=$2 checksum=$3
    if [ ! -f "$downloads/$name" ]; then
        curl --fail --location --retry 3 --connect-timeout 30 --max-time 900 "$url" -o "$downloads/$name.part"
        printf '%s  %s\n' "$checksum" "$downloads/$name.part" | sha256sum --check --status
        mv "$downloads/$name.part" "$downloads/$name"
    fi
    printf '%s  %s\n' "$checksum" "$downloads/$name" | sha256sum --check --status
}

while IFS=$'\t' read -r name url checksum; do
    fetch "$name" "$url" "$checksum"
done < <(jq -er '.archives[] | [.name,.url,.sha256] | @tsv' "$recipe/manifest.json")
cp "$recipe/kindlehf.cmake" "$sdk/kindlehf.cmake"

if [ ! -x "$sdk/x-tools/arm-kindlehf-linux-gnueabihf/bin/arm-kindlehf-linux-gnueabihf-gcc" ]; then
    # Existing writable directories avoid read-only archive modes on Mac mounts.
    tar -tf "$downloads/kindlehf.tar.zst" | while IFS= read -r path; do
        case "$path" in */) mkdir -p "$sdk/$path" ;; esac
    done
    tar --no-same-owner --no-same-permissions --no-overwrite-dir \
        -xf "$downloads/kindlehf.tar.zst" -C "$sdk"
    chmod -R u+w "$sdk/x-tools"
fi
for module in qtbase qtsensors; do
    if [ ! -d "$sources/$module-everywhere-src-6.8.3" ]; then
        tar -xf "$downloads/$module-everywhere-src-6.8.3.tar.xz" -C "$sources"
    fi
done
# glibc BZ 11941 can assert when Qt closes plugins from its process finalizer.
qt_patch=$recipe/patches/qt-finalizer-unload.patch
qt_source=$sources/qtbase-everywhere-src-6.8.3
if patch --dry-run --forward --batch --silent -p1 -d "$qt_source" < "$qt_patch"; then
    patch --forward --batch --silent -p1 -d "$qt_source" < "$qt_patch"
else
    patch --dry-run --reverse --batch --silent -p1 -d "$qt_source" < "$qt_patch"
fi
if [ ! -d "$sources/FBInk-886f25f13368859ad8a899b88d04c26e19cda32e" ]; then
    tar -xf "$downloads/fbink-886f25f.tar.gz" -C "$sources"
fi
if [ ! -f "$sources/FBInk-886f25f13368859ad8a899b88d04c26e19cda32e/stb/stb_image.h" ]; then
    tar -xf "$downloads/stb-dfa32fac.tar.gz" --strip-components=1 \
        -C "$sources/FBInk-886f25f13368859ad8a899b88d04c26e19cda32e/stb"
fi
if [ ! -d "$sources/zlib-1.3.1" ]; then
    tar -xf "$downloads/zlib-1.3.1.tar.gz" -C "$sources"
fi
cmake -S "$sources/zlib-1.3.1" -B "$sdk/zlib-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_TOOLCHAIN_FILE="$sdk/kindlehf.cmake" \
    -DCMAKE_INSTALL_PREFIX="$sdk/runtime"
cmake --build "$sdk/zlib-build" --parallel "$jobs"
cmake --install "$sdk/zlib-build"

export PATH="$sdk/x-tools/arm-kindlehf-linux-gnueabihf/bin:$PATH"
if [ ! -d "$sources/openssl-openssl-3.5.9" ]; then
    tar -xf "$downloads/openssl-3.5.9.tar.gz" -C "$sources"
fi
mkdir -p "$sdk/openssl-build"
(
    cd "$sdk/openssl-build"
    openssl_arguments=(linux-armv4 shared no-tests
        --cross-compile-prefix=arm-kindlehf-linux-gnueabihf-
        --prefix="$sdk/openssl" --libdir=lib --openssldir=/etc/ssl
        -march=armv7-a -mfpu=neon -mfloat-abi=hard)
    configured_arguments=
    if [[ -f configdata.pm ]]; then
        configured_arguments=$(perl -I. -Mconfigdata -e 'print join "\n", @{$configdata::config{perlargv}}' 2>/dev/null) || configured_arguments=
    fi
    # Configure rewrites build headers and recompiles OpenSSL even when its
    # arguments are unchanged. Reuse its own recorded configuration instead.
    if [[ "$configured_arguments" != "$(printf '%s\n' "${openssl_arguments[@]}")" ]]; then
        perl "$sources/openssl-openssl-3.5.9/Configure" "${openssl_arguments[@]}"
    fi
    make -j "$jobs"
    make install_sw
)

cmake -S "$sources/qtbase-everywhere-src-6.8.3" -B "$sdk/host-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk/qt-host" \
    -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF -DFEATURE_gui=OFF \
    -DFEATURE_network=OFF -DFEATURE_sql=OFF -DFEATURE_dbus=OFF \
    -DFEATURE_icu=OFF -DFEATURE_glib=OFF
cmake --build "$sdk/host-build" --parallel "$jobs"
cmake --install "$sdk/host-build"

cmake -S "$sources/qtbase-everywhere-src-6.8.3" -B "$sdk/target-build" -G Ninja \
    -U 'TEST_openssl*' \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk/qt" \
    -DCMAKE_TOOLCHAIN_FILE="$sdk/kindlehf.cmake" \
    -DQT_HOST_PATH="$sdk/qt-host" -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF \
    -DINPUT_opengl=no -DFEATURE_opengl=OFF -DFEATURE_xcb=OFF -DFEATURE_eglfs=OFF \
    -DFEATURE_linuxfb=ON -DFEATURE_evdev=ON -DFEATURE_tslib=OFF \
    -DFEATURE_libinput=OFF -DFEATURE_fontconfig=OFF -DFEATURE_system_freetype=OFF \
    -DFEATURE_system_harfbuzz=OFF -DFEATURE_system_png=OFF -DFEATURE_system_jpeg=OFF \
    -DFEATURE_system_zlib=OFF -DFEATURE_icu=OFF -DFEATURE_glib=OFF \
    -DFEATURE_dbus=OFF -DINPUT_openssl=linked -DOPENSSL_ROOT_DIR="$sdk/openssl" \
    -DFEATURE_ssl=ON -DFEATURE_openssl=ON -DFEATURE_openssl_linked=ON \
    -DFEATURE_openssl_runtime=OFF -DFEATURE_sql=ON \
    -DFEATURE_sql_sqlite=ON -DFEATURE_system_sqlite=OFF \
    -DQT_QPA_DEFAULT_PLATFORM=kindle
cmake --build "$sdk/target-build" --parallel "$jobs"
cmake --install "$sdk/target-build"

cmake -S "$sources/qtsensors-everywhere-src-6.8.3" -B "$sdk/sensors-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk/qt" \
    -DCMAKE_TOOLCHAIN_FILE="$sdk/qt/lib/cmake/Qt6/qt.toolchain.cmake" \
    -DQT_HOST_PATH="$sdk/qt-host" -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF
cmake --build "$sdk/sensors-build" --parallel "$jobs"
cmake --install "$sdk/sensors-build"

export PATH="$sdk/x-tools/arm-kindlehf-linux-gnueabihf/bin:$PATH"
fbink=$sources/FBInk-886f25f13368859ad8a899b88d04c26e19cda32e
fbink_patch=$recipe/patches/fbink-state-dump.patch
if patch --dry-run --forward --batch --silent -p1 -d "$fbink" < "$fbink_patch"; then
    patch --forward --batch --silent -p1 -d "$fbink" < "$fbink_patch"
else
    patch --dry-run --reverse --batch --silent -p1 -d "$fbink" < "$fbink_patch"
fi
sed -i 's/^FBINK_VERSION:=.*/FBINK_VERSION:=886f25f/' "$fbink/Makefile"
# FBInk declares this prerequisite for every target, but only Kobo uses I2C.
make -C "$fbink" -o libi2c.built -j "$jobs" sharedlib KINDLE=true MINIMAL=true IMAGE=true DRAW=true \
    CROSS_TC=arm-kindlehf-linux-gnueabihf FBINK_VERSION=886f25f
mkdir -p "$sdk/fbink/lib" "$sdk/fbink/include"
cp -a "$fbink"/Release/libfbink.so* "$sdk/fbink/lib/"
cp "$fbink/fbink.h" "$sdk/fbink/include/"
printf 'Qt 6.8.3; koxtoolchain 2026.08 kindlehf; FBInk 886f25f; OpenSSL 3.5.9\n' > "$sdk/ready.txt"
