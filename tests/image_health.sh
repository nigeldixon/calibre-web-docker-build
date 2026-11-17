#!/bin/sh
# Start the container and wait for calibre-web to answer on its port.
set -eu

image="${1:?usage: image_health.sh <image>}"
engine="${CONTAINER_ENGINE:-docker}"
port="${HEALTH_PORT:-18083}"
cid="$("$engine" run -d -p "$port:8083" -e KCC_WATCH_ENABLED=false "$image")"

cleanup() { "$engine" rm -f "$cid" >/dev/null 2>&1 || true; }
trap cleanup EXIT

i=0
while [ "$i" -lt 150 ]; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)"
    case "$code" in
        200|302) echo "calibre-web responded with HTTP $code"; exit 0 ;;
    esac
    i=$((i + 1))
    sleep 2
done

echo "FAIL: calibre-web did not respond"
"$engine" logs "$cid" 2>&1 | tail -30 || true
exit 1
