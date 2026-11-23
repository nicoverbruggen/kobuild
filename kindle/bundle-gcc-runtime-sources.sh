#!/usr/bin/env bash
set -euo pipefail

recipe=/usr/src/kobuild/kindle/recipe
tc=/sdk/x-tools/arm-kindlehf-linux-gnueabihf
target=${tc##*/}
compiler=$tc/bin/$target-g++
compiler_hash=$(jq -er '.archives[] | select(.kind == "compiler") | .sha256' "$recipe/manifest.json")
bundle=/usr/src/kobuild/kindle/gcc-runtime
mkdir -p "$bundle"
cp "$recipe/gcc-runtime-sources.json" "$bundle/manifest.json"
cd "$bundle"

# A compiler update must also identify the recipe and sources for that binary.
jq -e --arg hash "$compiler_hash" --arg version "$("$compiler" -dumpfullversion)" \
    '.compiler_archive_sha256 == $hash and .gcc_version == $version' manifest.json >/dev/null
archives=$(jq -er '.archives[] | [.name,.url,.sha256] | @tsv' manifest.json)
while IFS=$'\t' read -r name url hash; do
    curl -fSL --retry 3 "$url" -o "$name"
    printf '%s  %s\n' "$hash" "$name" | sha256sum --check
done <<<"$archives"

version=$(jq -er .gcc_version manifest.json)
for license in COPYING3 COPYING.RUNTIME; do
    tar -xOf "gcc-$version.tar.xz" "gcc-$version/$license" > "$license"
done
bzip2 -dc "$tc/share/$target-ct-ng.config.bz2" > ct-ng.config
"$compiler" -v > compiler-version.txt 2>&1
