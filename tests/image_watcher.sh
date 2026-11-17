#!/bin/sh
# Exercise the watcher inside the image: success, failure -> .failed/, and inotify.
set -eu

image="${1:?usage: image_watcher.sh <image>}"
engine="${CONTAINER_ENGINE:-docker}"
fixtures="$(cd "$(dirname "$0")/fixtures" && pwd)"
tmp="$(mktemp -d)"
cid=""

cleanup() {
    [ -n "$cid" ] && "$engine" rm -f "$cid" >/dev/null 2>&1 || true
    rm -rf "$tmp"
}
trap cleanup EXIT

start() {
    cid="$("$engine" run -d \
        -e KCC_WATCH_SETTLE=1 \
        -e KCC_WATCH_POLL=1 \
        -e KCC_WATCH_FAIL_THRESHOLD=1 \
        -e KCC_WATCH_USE_INOTIFY="$1" \
        "$image" sleep 900)"
}

wait_for() {
    i=0
    while [ "$i" -lt 120 ]; do
        if "$engine" exec "$cid" test -e "$1"; then return 0; fi
        i=$((i + 1))
        sleep 2
    done
    return 1
}

# Wait for a path to disappear. The watcher deletes the source only after
# kcc-c2e returns, which can lag the output file appearing (especially under
# emulation), so this must not be an immediate check.
wait_gone() {
    i=0
    while [ "$i" -lt 120 ]; do
        if ! "$engine" exec "$cid" test -e "$1"; then return 0; fi
        i=$((i + 1))
        sleep 2
    done
    return 1
}

fail() {
    echo "FAIL: $1"
    "$engine" logs "$cid" 2>&1 | tail -25 || true
    exit 1
}

# success: convert the archive and delete the source
start false
"$engine" cp "$fixtures/sample.cbz" "$cid:/c2e_comics/sample.cbz"
wait_for /calibredrop/sample.kepub.epub || fail "no output for sample.cbz"
wait_gone /c2e_comics/sample.cbz || fail "source not deleted after success"
echo "watcher success OK"
"$engine" rm -f "$cid" >/dev/null 2>&1; cid=""

# failure: an invalid archive is moved to .failed/
printf 'not a real archive\n' > "$tmp/corrupt.cbz"
start false
"$engine" cp "$tmp/corrupt.cbz" "$cid:/c2e_comics/corrupt.cbz"
wait_for /c2e_comics/.failed/corrupt.cbz || fail "corrupt file not moved to .failed/"
wait_gone /c2e_comics/corrupt.cbz || fail "corrupt source still present"
echo "watcher failure OK"
"$engine" rm -f "$cid" >/dev/null 2>&1; cid=""

# inotify: a real 7z archive is converted with the inotify accelerator enabled
start true
"$engine" cp "$fixtures/sample.7z" "$cid:/c2e_comics/sample.7z"
wait_for /calibredrop/sample.kepub.epub || fail "no output for sample.7z (inotify)"
"$engine" logs "$cid" 2>&1 | grep -q "inotify enabled" || fail "inotify was not enabled"
echo "watcher inotify OK"
