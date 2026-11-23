#!/usr/bin/env bash
# Compile/link checks only. The compiler sysroot's loader is not a stock Kindle
# runtime; firmware execution checks belong to the consuming application.
set -euo pipefail
[[ $# == 0 ]] || { echo 'Usage: kobuild-check' >&2; exit 2; }
sdk=/sdk
tc=$sdk/x-tools/arm-kindlehf-linux-gnueabihf
compiler=$tc/bin/arm-kindlehf-linux-gnueabihf-g++
readelf=$tc/bin/arm-kindlehf-linux-gnueabihf-readelf
manifest=/usr/share/doc/kobuild/kindle-manifest.json
[[ $(uname -m) == x86_64 ]]
test -s "$sdk/ready.txt"
test -f "$sdk/kindlehf.cmake"
jq -e '.host == "amd64" and .glibc_maximum == "2.20"' "$manifest" >/dev/null
qt_version=$(jq -er .qt_version "$manifest")
for tool in "$compiler" "$sdk/qt-host/libexec/moc" "$sdk/qt-host/libexec/rcc"; do
    file -L "$tool" | grep -q 'x86-64'
done
for file in LICENSE NOTICE qt-licenses/LGPL-3.0-only.txt; do
    test -s "/usr/share/doc/kobuild/$file"
done
while IFS=$'\t' read -r name hash; do
    printf '%s  %s\n' "$hash" "/usr/src/kobuild/kindle/$name" | sha256sum --check --status
done < <(jq -er '.archives[] | [.name,.sha256] | @tsv' "$manifest")
runtime_sources=/usr/src/kobuild/kindle/gcc-runtime
runtime_manifest=$runtime_sources/manifest.json
archives=$(jq -er '.archives[] | [.name,.sha256] | @tsv' "$runtime_manifest")
while IFS=$'\t' read -r name hash; do
    printf '%s  %s\n' "$hash" "$runtime_sources/$name" | sha256sum --check --status
done <<<"$archives"
for file in COPYING3 COPYING.RUNTIME compiler-version.txt ct-ng.config; do
    test -s "$runtime_sources/$file"
done
bzip2 -dc "$tc/share/${tc##*/}-ct-ng.config.bz2" | cmp "$runtime_sources/ct-ng.config"
for patch in qt-finalizer-unload.patch fbink-state-dump.patch; do
    test -s "/usr/src/kobuild/kindle/recipe/patches/$patch"
done
for feature in ssl; do
    grep -q "^#define QT_FEATURE_$feature 1" "$sdk/qt/include/QtNetwork/qtnetwork-config.h"
done
grep -q '^#define QT_FEATURE_openssl_linked 1' "$sdk/qt/include/QtCore/qconfig.h"
for file in qt/plugins/tls/libqopensslbackend.so qt/plugins/sqldrivers/libqsqlite.so \
    openssl/lib/libssl.so.3 openssl/lib/libcrypto.so.3 fbink/include/fbink.h; do
    test -s "$sdk/$file"
done

work=$(mktemp -d /tmp/kobuild-kindle-check.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat >"$work/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.22)
project(kindle_check LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 ${KOBUILD_QT_VERSION} EXACT REQUIRED COMPONENTS Core Gui Widgets Network Sensors Sql)
qt_add_executable(check main.cpp)
qt_add_resources(check probe PREFIX "/" FILES message.txt)
target_link_libraries(check PRIVATE Qt6::Widgets Qt6::Network Qt6::Sensors Qt6::Sql Qt6::GuiPrivate)
EOF
cat >"$work/main.cpp" <<'EOF'
#include <QApplication>
#include <QFile>
#include <QNetworkAccessManager>
#include <QOrientationSensor>
#include <QSqlDatabase>
#include <QSslSocket>
#include <QWidget>
#include <qpa/qplatformintegration.h>
class Check : public QObject {
    Q_OBJECT
};
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QWidget widget;
    QOrientationSensor sensor;
    QNetworkAccessManager network;
    return widget.width() + QSqlDatabase::drivers().size() + QSslSocket::supportsSsl()
        + QFile(QStringLiteral(":/message.txt")).exists() + (sensor.reading() != nullptr);
}
#include "main.moc"
EOF
printf 'Kindle SDK resource check\n' >"$work/message.txt"
cmake -S "$work" -B "$work/build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$sdk/qt/lib/cmake/Qt6/qt.toolchain.cmake" \
    -DQT_CHAINLOAD_TOOLCHAIN_FILE="$sdk/kindlehf.cmake" -DQT_HOST_PATH="$sdk/qt-host" \
    -DKOBUILD_QT_VERSION="$qt_version"
cmake --build "$work/build" --parallel 2
"$readelf" -A "$work/build/check" | grep -q 'Tag_ABI_VFP_args: VFP registers'
"$readelf" -A "$work/build/check" | grep -q 'Tag_Advanced_SIMD_arch: NEONv1'
"$readelf" -l "$work/build/check" | grep -q '/lib/ld-linux-armhf.so.3'
for module in Widgets Network Sensors Sql; do
    "$readelf" -d "$work/build/check" | grep -q "libQt6${module}.so.6"
done

check_elf() {
    local binary=$1 header needed version major minor resolved
    header=$("$readelf" -h "$binary")
    grep -q 'Class:.*ELF32' <<<"$header"
    grep -q 'Machine:.*ARM' <<<"$header"
    grep -q 'hard-float ABI' <<<"$header"
    while IFS= read -r version; do
        major=${version%%.*}; minor=${version#*.}; minor=${minor%%.*}
        (( major < 2 || (major == 2 && minor <= 20) )) || {
            echo "GLIBC_$version exceeds the glibc 2.20 target: $binary" >&2; return 1;
        }
    done < <("$readelf" --version-info --wide "$binary" | sed -n 's/.*Name: GLIBC_\([0-9.]*\).*/\1/p')
    while IFS= read -r needed; do
        resolved=
        for directory in "$sdk/qt/lib" "$sdk/openssl/lib" "$sdk/runtime/lib" "$sdk/fbink/lib"; do
            if [[ -f $directory/$needed ]]; then resolved=$directory/$needed; break; fi
        done
        if [[ -z $resolved ]]; then
            resolved=$("$compiler" "-print-file-name=$needed")
        fi
        [[ $resolved == /* && -f $resolved ]] || {
            echo "Unresolved SDK dependency $needed: $binary" >&2; return 1;
        }
    done < <("$readelf" -d "$binary" | sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p')
}
check_elf "$work/build/check"
while IFS= read -r -d '' library; do check_elf "$library"; done < <(
    find "$sdk/qt/lib" "$sdk/qt/plugins" "$sdk/openssl/lib" "$sdk/runtime/lib" "$sdk/fbink/lib" \
        -type f \( -name '*.so' -o -name '*.so.*' \) -print0)
for name in libstdc++.so.6 libgcc_s.so.1 libatomic.so.1; do
    check_elf "$("$compiler" "-print-file-name=$name")"
done
echo 'Kindle SDK: Qt code generation, private headers, SQL/TLS plugins, ARM hard-float and glibc <= 2.20 checks passed'
