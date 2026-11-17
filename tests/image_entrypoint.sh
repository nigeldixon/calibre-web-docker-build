#!/bin/sh
# Verify the entrypoint starts the watcher by default and honours the disable switch.
set -eu

image="${1:?usage: image_entrypoint.sh <image>}"
engine="${CONTAINER_ENGINE:-docker}"

disabled="$("$engine" run --rm -e KCC_WATCH_ENABLED=false "$image" sh -c 'echo CMD_RAN')"
echo "$disabled" | grep -q CMD_RAN || { echo "FAIL: CMD did not run when disabled"; exit 1; }
if echo "$disabled" | grep -q "Starting kcc-watch"; then
    echo "FAIL: watcher started when disabled"
    exit 1
fi

enabled="$("$engine" run --rm "$image" sh -c 'echo CMD_RAN; cat /proc/1/comm')"
echo "$enabled" | grep -q CMD_RAN || { echo "FAIL: CMD did not run by default"; exit 1; }
echo "$enabled" | grep -q "Starting kcc-watch" || { echo "FAIL: watcher did not start by default"; exit 1; }
echo "$enabled" | grep -q "tini" || { echo "FAIL: tini is not PID 1"; exit 1; }

echo "entrypoint OK"
