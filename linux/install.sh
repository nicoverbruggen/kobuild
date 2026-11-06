#!/bin/bash
# Installs the official Qt desktop archives of this host architecture into
# $QT_PATH. Every archive is checked against manifest.json before use.
set -euo pipefail
cd "$(dirname "$0")"
cache=/var/cache/kobuild-linux
docs=/usr/share/doc/kobuild
sources=/usr/src/kobuild/linux
arch=$(dpkg --print-architecture)
jq -e --arg arch "$arch" '.hosts[$arch]' manifest.json > /dev/null
mkdir -p "$cache" "$docs/qt-licenses" "$sources" "$QT_PATH"
archive=''
trap '[[ -z "$archive" ]] || rm -f "$archive.partial"' EXIT

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

while IFS=$'\t' read -r name url hash subdirectory; do
    download "$name" "$url" "$hash"
    7z x -y -bso0 -o"$QT_PATH/${subdirectory:-.}" "$archive"
done < <(jq -r --arg arch "$arch" '.hosts[$arch].archives[] | [.file,.url,.sha256,(.subdirectory // "")] | @tsv' manifest.json)

while IFS=$'\t' read -r name url hash; do
    download "$name" "$url" "$hash"
    cp "$archive" "$sources/$name"
    tar -xJf "$archive" --strip-components=1 -C "$docs/qt-licenses" LICENSES
done < <(jq -r '.sources[] | [.file,.url,.sha256] | @tsv' manifest.json)

# The official kit directory name differs per architecture. One fixed path
# keeps CMAKE_PREFIX_PATH the same on both hosts.
printf '[Paths]\nPrefix=..\n' > "$QT_PATH/bin/qt.conf"
jq --arg arch "$arch" '{qt_version, host: $arch, kit: .hosts[$arch].kit, archives: .hosts[$arch].archives, sources}' \
    manifest.json > "$docs/linux-manifest.json"
