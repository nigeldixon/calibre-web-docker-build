#!/bin/sh
set -e

case "${KCC_WATCH_ENABLED:-true}" in
    1|true|TRUE|yes|YES|on|ON)
        echo "Starting kcc-watch..."
        python3 /usr/local/bin/kcc_watch.py &
        ;;
esac

exec "$@"
