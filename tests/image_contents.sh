#!/bin/sh
# Assert the built image contains the expected tools, directories and defaults.
set -eu

image="${1:?usage: image_contents.sh <image>}"
engine="${CONTAINER_ENGINE:-docker}"

"$engine" run --rm --entrypoint /bin/sh "$image" -euc '
    for tool in tini inotifywait 7z kcc-c2e kcc-c2p kepubify python3; do
        command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool"; exit 1; }
    done
    for dir in /c2e_comics /c2e_manga /calibredrop; do
        [ -d "$dir" ] || { echo "missing dir: $dir"; exit 1; }
    done
    [ -x /usr/local/bin/docker-entrypoint.sh ] || { echo "entrypoint not executable"; exit 1; }
    [ -x /usr/local/bin/kcc_watch.py ] || { echo "watcher not executable"; exit 1; }
    [ "${KCC_WATCH_ENABLED:-}" = "true" ] || { echo "KCC_WATCH_ENABLED is not true"; exit 1; }
    echo "image contents OK"
'
