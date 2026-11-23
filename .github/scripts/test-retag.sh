#!/bin/bash
set -euo pipefail
mkdir -p build
work=$(mktemp -d "$PWD/build/retag-check.XXXXXX")
trap 'rm -rf "$work"' EXIT
cat > "$work/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$RETAG_LOG"
SH
chmod +x "$work/docker"
export PATH="$work:$PATH" RETAG_LOG="$work/calls" GITHUB_REPOSITORY=example/sdk
export PREVIOUS_TAG=v1.0-ci.1 TARGETS='["android"]' RELEASE_TAG=v1.0-ci.2
all_targets=$(jq -c . .github/sdk-targets.json)
expected_retags=$(jq 'length - 1' <<< "$all_targets")
bash .github/scripts/retag.sh
[[ $(wc -l < "$RETAG_LOG") -eq $expected_retags ]]
grep -Fx 'buildx imagetools create --tag ghcr.io/example/sdk:linux-v1.0-ci.2 ghcr.io/example/sdk:linux-v1.0-ci.1' "$RETAG_LOG"
grep -Fx 'buildx imagetools create --tag ghcr.io/example/sdk:kindle-v1.0-ci.2 ghcr.io/example/sdk:kindle-v1.0-ci.1' "$RETAG_LOG"
if grep -q android "$RETAG_LOG"; then exit 1; fi
: > "$RETAG_LOG"
RELEASE_TAG=v1.0 bash .github/scripts/retag.sh
grep -Fx 'buildx imagetools create --tag ghcr.io/example/sdk:linux-v1.0 --tag ghcr.io/example/sdk:linux ghcr.io/example/sdk:linux-v1.0-ci.1' "$RETAG_LOG"
grep -Fx 'buildx imagetools create --tag ghcr.io/example/sdk:kindle-v1.0 --tag ghcr.io/example/sdk:kindle ghcr.io/example/sdk:kindle-v1.0-ci.1' "$RETAG_LOG"
: > "$RETAG_LOG"
if PREVIOUS_TAG= bash .github/scripts/retag.sh; then exit 1; fi
[[ ! -s "$RETAG_LOG" ]]
TARGETS='["kindle"]' bash .github/scripts/retag.sh
[[ $(wc -l < "$RETAG_LOG") -eq $expected_retags ]]
if grep -q kindle "$RETAG_LOG"; then exit 1; fi
: > "$RETAG_LOG"
PREVIOUS_TAG= TARGETS="$all_targets" bash .github/scripts/retag.sh
[[ ! -s "$RETAG_LOG" ]]
echo 'PASS: SDK prerelease reuse and stable aliases'
