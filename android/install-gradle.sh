#!/bin/bash
# Keep Qt's wrapper usable with an empty application cache and no distribution download.
set -euo pipefail
manifest=/usr/local/lib/kobuild/manifest.json
version=$(jq -er '.gradle.version' "$manifest")
url=$(jq -er '.gradle.url' "$manifest")
hash=$(jq -er '.gradle.sha256' "$manifest")
name="gradle-$version-bin.zip"
properties="$QT_ANDROID_ARM64_PATH/src/3rdparty/gradle/gradle/wrapper/gradle-wrapper.properties"
# Fail on a Qt upgrade until the Gradle pin is reviewed with its new wrapper.
grep -Fx "distributionUrl=${url//:/\\:}" "$properties"
cache=/var/cache/kobuild-android
mkdir -p "$cache" /opt/gradle
archive="$cache/$name"
if [[ ! -f "$archive" ]] || ! echo "$hash  $archive" | sha256sum -c --status; then
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 --max-time 600 \
        --output "$archive.partial" "$url"
    echo "$hash  $archive.partial" | sha256sum -c -
    mv "$archive.partial" "$archive"
fi
install -m 644 "$archive" "/opt/gradle/$name"
sed -i "s|^distributionUrl=.*|distributionUrl=file\\\\:/opt/gradle/$name|" "$properties"
# The wrapper also verifies the distribution after copying it to the writable cache.
sed -i '/^distributionSha256Sum=/d' "$properties"
printf 'distributionSha256Sum=%s\n' "$hash" >> "$properties"
