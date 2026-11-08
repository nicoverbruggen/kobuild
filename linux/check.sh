#!/bin/bash
# Checks the Linux desktop SDK offline: tools, Qt version, notices, source
# archives, and a Qt program that is built, linked and run headless.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: kobuild-check' >&2; exit 2; }
for tool in cmake ninja make patch perl pkg-config zip gcc g++ ccache ld.lld; do
    command -v "$tool" >/dev/null
done
docs=/usr/share/doc/kobuild
manifest="$docs/linux-manifest.json"
[[ $(jq -r .host "$manifest") == "$(dpkg --print-architecture)" ]]
[[ $(jq -r .qt_version "$manifest") == 6.11.3 ]]
for notice in LICENSE NOTICE qt-licenses/LGPL-3.0-only.txt icu-LICENSE.txt; do
    test -s "$docs/$notice"
done
while IFS=$'\t' read -r name hash; do
    echo "$hash  /usr/src/kobuild/linux/$name" | sha256sum -c -
done < <(jq -r '.sources[] | [.file,.sha256] | @tsv' "$manifest")
for plugin in platforms/libqoffscreen.so sqldrivers/libqsqlite.so; do
    test -f "$QT_PATH/plugins/$plugin"
done
work=$(mktemp -d /tmp/kobuild-linux-check.XXXXXX)
trap 'rm -rf "$work"' EXIT
cp -R /usr/local/lib/kobuild/smoke/. "$work/"
cd "$work"
export CCACHE_DIR="$work/ccache"
cmake --preset linux -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld
cmake --build --preset linux
QT_QPA_PLATFORM=offscreen ./build/check
# A clean rebuild must reuse cached compilation and still link with LLD.
ccache --zero-stats
cmake --build --preset linux --clean-first
ccache --print-stats | awk '$1 == "direct_cache_hit" || $1 == "preprocessed_cache_hit" {hits += $2} END {exit !(hits > 0)}'
readelf --string-dump=.comment build/check | grep -q 'Linker: LLD'
QT_QPA_PLATFORM=offscreen ./build/check
echo 'Qt desktop build, link and headless run checks passed'
