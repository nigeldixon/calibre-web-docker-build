#!/bin/sh
# Smoke-test a built calibre-web image by running a real kcc-c2e conversion.
# Usage: tests/image_smoke.sh <image>
set -eu

image="${1:?usage: image_smoke.sh <image>}"
engine="${CONTAINER_ENGINE:-docker}"
fixtures="$(cd "$(dirname "$0")/fixtures" && pwd)"

"$engine" run -i --rm -e KCC_WATCH_ENABLED=false "$image" sh -eu -c '
    command -v kcc-c2e
    cat > /tmp/sample.cbz
    mkdir -p /tmp/out
    kcc-c2e -p KoL -o /tmp/out /tmp/sample.cbz
    test -n "$(ls -A /tmp/out)"
    ls -l /tmp/out
' < "$fixtures/sample.cbz"

echo "kcc-c2e smoke test passed for $image"
