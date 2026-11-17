#!/bin/sh
# Assert the built image contains the expected tools, directories and defaults.
# Usage: image_contents.sh <image> [arch]
#   arch is optional; when given (amd64/arm64) the container's machine type is
#   checked and the arch-specific binaries are executed.
set -eu

image="${1:?usage: image_contents.sh <image> [arch]}"
engine="${CONTAINER_ENGINE:-docker}"
arch="${2:-}"

case "$arch" in
    amd64) machine=x86_64 ;;
    arm64) machine=aarch64 ;;
    "") machine="" ;;
    *) machine="$arch" ;;
esac

"$engine" run --rm --entrypoint /bin/sh -e "EXPECT_MACHINE=$machine" "$image" -euc '
    for tool in tini inotifywait 7z kcc-c2e kcc-c2p kepubify python3; do
        command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool"; exit 1; }
    done
    for dir in /c2e_comics /c2e_manga /calibredrop; do
        [ -d "$dir" ] || { echo "missing dir: $dir"; exit 1; }
    done
    [ -x /usr/local/bin/docker-entrypoint.sh ] || { echo "entrypoint not executable"; exit 1; }
    [ -x /usr/local/bin/kcc_watch.py ] || { echo "watcher not executable"; exit 1; }
    [ "${KCC_WATCH_ENABLED:-}" = "true" ] || { echo "KCC_WATCH_ENABLED is not true"; exit 1; }

    if [ -n "${EXPECT_MACHINE:-}" ]; then
        got="$(uname -m)"
        [ "$got" = "$EXPECT_MACHINE" ] || {
            echo "arch mismatch: expected $EXPECT_MACHINE, got $got"
            exit 1
        }
    fi

    # Arch-specific binaries must execute, not merely exist: an image built for
    # the wrong platform would still contain files of the right name.
    kepubify --version >/dev/null 2>&1 || { echo "kepubify does not run"; exit 1; }
    /opt/kcc_venv/bin/python3 -c "import PySide6.QtCore" >/dev/null 2>&1 || {
        echo "KCC venv cannot import PySide6"
        exit 1
    }

    echo "image contents OK (machine=$(uname -m))"
'
