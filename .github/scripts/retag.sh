#!/bin/bash
# Reuse the same release whose recipe commit was used to select changed SDKs.
set -euo pipefail
image="ghcr.io/${GITHUB_REPOSITORY,,}"
unchanged=$(jq -r --argjson built "$TARGETS" '. - $built | join("\n")' "$(dirname "$0")/../sdk-targets.json")
[[ -n "$unchanged" ]] || exit 0
while IFS= read -r target; do
    [[ -n "$PREVIOUS_TAG" ]] || { echo 'Missing previous release for unchanged SDK' >&2; exit 1; }
    echo "Tagging $target-$PREVIOUS_TAG as $target-$RELEASE_TAG"
    tags=(--tag "$image:$target-$RELEASE_TAG")
    if [[ "$RELEASE_TAG" != *-* ]]; then tags+=(--tag "$image:$target"); fi
    docker buildx imagetools create "${tags[@]}" "$image:$target-$PREVIOUS_TAG"
done <<< "$unchanged"
