#!/bin/sh
set -eu
cd "$(dirname "$0")"
target=${1:-qt6}
case "$target" in qt5|qt6) ;; *) echo 'Usage: ./build.sh [qt5|qt6]' >&2; exit 2;; esac
jobs=${JOBS:-2}
case "$jobs" in ''|*[!0-9]*|0) echo 'JOBS must be a positive integer' >&2; exit 2;; esac
engine=${CONTAINER_ENGINE:-}
if [ -z "$engine" ]; then
    if command -v docker >/dev/null 2>&1; then engine=docker
    elif command -v podman >/dev/null 2>&1; then engine=podman
    else echo 'Install Docker or Podman' >&2; exit 1; fi
fi
"$engine" build --build-arg "JOBS=$jobs" -f "$target/Dockerfile" -t "localhost/kobuild:$target" .
"$engine" run --rm --network none "localhost/kobuild:$target" python3 /usr/local/bin/kobuild-check
