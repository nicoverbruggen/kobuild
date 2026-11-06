#!/bin/bash
# Checks the Linux desktop SDK offline: tools, Qt version, notices, source
# archives, and a Qt program that is built, linked and run headless.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: kobuild-check' >&2; exit 2; }
for tool in cmake ninja make patch perl pkg-config zip gcc g++; do
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
cmake --preset linux
cmake --build --preset linux
QT_QPA_PLATFORM=offscreen ./build/check
echo 'Qt desktop build, link and headless run checks passed'
