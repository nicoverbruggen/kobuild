#!/bin/bash
# Exercise the same wrapper androiddeployqt copies, without reusing a Gradle cache.
set -euo pipefail
manifest=/usr/local/lib/kobuild/manifest.json
version=$(jq -er '.gradle.version' "$manifest")
hash=$(jq -er '.gradle.sha256' "$manifest")
wrapper="$QT_ANDROID_ARM64_PATH/src/3rdparty/gradle/gradle/wrapper"
grep -Fx "distributionUrl=file\\:/opt/gradle/gradle-$version-bin.zip" "$wrapper/gradle-wrapper.properties"
grep -Fx "distributionSha256Sum=$hash" "$wrapper/gradle-wrapper.properties"
echo "$hash  /opt/gradle/gradle-$version-bin.zip" | sha256sum -c -
work=$(mktemp -d /tmp/kobuild-gradle-check.XXXXXX)
trap 'rm -rf "$work"' EXIT
GRADLE_USER_HOME="$work" "$JAVA_HOME/bin/java" -classpath "$wrapper/gradle-wrapper.jar" \
    org.gradle.wrapper.GradleWrapperMain --version > "$work/version.txt"
grep -Fx "Gradle $version" "$work/version.txt"
