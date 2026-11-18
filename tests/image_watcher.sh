#!/bin/sh
# Exercise the watcher inside the image: success, manga rtl, PDF, failure -> .failed/, and inotify.
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

# manga: the manga folder must produce a right-to-left book. -m is applied by
# default; without it kcc-c2e lays the pages out left-to-right.
cat > "$tmp/check_rtl.py" <<'PY'
import glob
import sys
import zipfile

path = glob.glob("/calibredrop/*.kepub.epub")[0]
z = zipfile.ZipFile(path)
opf = [n for n in z.namelist() if n.endswith(".opf")][0]
data = z.read(opf).decode("utf-8", "replace")
rtl = 'page-progression-direction="rtl"' in data
print("page-progression-direction:", "rtl" if rtl else "not rtl")
sys.exit(0 if rtl else 1)
PY
start false
"$engine" cp "$fixtures/sample.cbz" "$cid:/c2e_manga/sample.cbz"
wait_for /calibredrop/sample.kepub.epub || fail "no output for /c2e_manga/sample.cbz"
wait_gone /c2e_manga/sample.cbz || fail "manga source not deleted after success"
"$engine" cp "$tmp/check_rtl.py" "$cid:/tmp/check_rtl.py"
"$engine" exec "$cid" /opt/kcc_venv/bin/python3 /tmp/check_rtl.py || fail "manga output is not right-to-left"
echo "watcher manga rtl OK"
"$engine" rm -f "$cid" >/dev/null 2>&1; cid=""

# pdf: a PDF is not an archive and must not be run through 7z validation
start false
"$engine" cp "$fixtures/sample.pdf" "$cid:/c2e_comics/sample.pdf"
wait_for /calibredrop/sample.kepub.epub || fail "no output for sample.pdf"
wait_gone /c2e_comics/sample.pdf || fail "source not deleted after PDF success"
echo "watcher pdf OK"
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
