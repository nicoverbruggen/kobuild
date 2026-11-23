#!/bin/bash
# Populate tags with the canonical name and any compatibility aliases.
sdk_release_tags() {
    local image=$1 target=$2 release=$3 name
    local names=("$target")
    case "$target" in nickel-qt5|nickel-qt6) names+=("${target#nickel-}") ;; esac
    tags=()
    for name in "${names[@]}"; do
        tags+=(--tag "$image:$name-$release")
        if [[ "$release" != *-* ]]; then tags+=(--tag "$image:$name"); fi
    done
}
