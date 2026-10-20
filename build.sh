#!/bin/sh
set -eu
cd "$(dirname "$0")"
target=${1:-qt6}
case "$target" in qt5|qt6|android) ;; *) echo 'Usage: ./build.sh [qt5|qt6|android]' >&2; exit 2;; esac
jobs=${JOBS:-2}
case "$jobs" in ''|*[!0-9]*|0) echo 'JOBS must be a positive integer' >&2; exit 2;; esac
engine=${CONTAINER_ENGINE:-}
if [ -z "$engine" ]; then
    if command -v docker >/dev/null 2>&1; then engine=docker
    elif command -v podman >/dev/null 2>&1; then engine=podman
    else echo 'Install Docker or Podman' >&2; exit 1; fi
fi
recipe="$target/Dockerfile"
runtime=python3
set --
if [ "$target" = android ]; then
    arch=${ANDROID_HOST_ARCH:-$(uname -m)}
    case "$arch" in
        arm64|aarch64) arch=arm64; recipe=android/Dockerfile.arm64; runtime=bash ;;
        amd64|x86_64) arch=amd64 ;;
        *) echo 'ANDROID_HOST_ARCH must be amd64 or arm64' >&2; exit 2 ;;
    esac
    set -- --platform "linux/$arch"
fi
"$engine" build "$@" --build-arg "JOBS=$jobs" -f "$recipe" -t "localhost/kobuild:$target" .
"$engine" run "$@" --rm --network none "localhost/kobuild:$target" "$runtime" /usr/local/bin/kobuild-check
if [ "$target" = android ]; then
    mkdir -p "build/android-gradle-$arch"
    "$engine" run "$@" --rm --user "$(id -u):$(id -g)" \
        -e HOME=/tmp -e ANDROID_USER_HOME=/tmp/.android -e GRADLE_USER_HOME=/gradle \
        --volume "$PWD/build/android-gradle-$arch:/gradle" \
        "localhost/kobuild:$target" "$runtime" /usr/local/bin/kobuild-check --apk
fi
