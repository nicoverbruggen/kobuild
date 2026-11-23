#!/bin/bash
# Add Sensors to the prepared Kobo Qt SDK. Qt Base and host tools are reused.
set -euo pipefail
tc=$1
spec=$2
jobs=${JOBS:-2}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "JOBS must be positive" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
archive=$work/sensors.tar.xz
if [[ $# -eq 3 ]]; then
    cp "$3" "$archive"
else
    curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 \
        "$(jq -er .url "$spec")" -o "$archive"
fi
printf '%s  %s\n' "$(jq -er .sha256 "$spec")" "$archive" | sha256sum --check -
tar -xf "$archive" -C "$work"
source_dir=$work/$(jq -er .directory "$spec")
# Preserve the exact source and recipe before configuration writes any files.
cp "$spec" "$work/sensors.json"
cp "$0" "$work/build-sensors.sh"
mkdir -p /usr/src/kobuild
XZ_OPT="-T2 -1" tar -C "$work" -cJf /usr/src/kobuild/qt6-sensors-source.tar.xz \
    "$(jq -er .directory "$spec")" sensors.json build-sensors.sh
cmake -S "$source_dir" -B "$work/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$tc/qt6" \
    -DCMAKE_TOOLCHAIN_FILE="$tc/toolchain.cmake" -DQT_HOST_PATH="$tc/host" \
    -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF
cmake --build "$work/build" --parallel "$jobs"
cmake --install "$work/build"
printf 'qtsensors %s sha256:%s\n' "$(jq -er .version "$spec")" \
    "$(jq -er .sha256 "$spec")" >> "$tc/manifest.txt"
