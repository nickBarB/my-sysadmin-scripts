#!/usr/bin/env bash
set -euo pipefail

monitor_pid=""
http_pid=""

cleanup() {
    trap - EXIT
    for pid in "$monitor_pid" "$http_pid"; do
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 0' TERM INT

/usr/local/bin/script.sh &
monitor_pid=$!
python3 -u -m http.server 8080 --bind 0.0.0.0 --directory /var/www &
http_pid=$!

# If either component stops, fail the container so systemd can restart it.
status=0
wait -n "$monitor_pid" "$http_pid" || status=$?
printf 'Monitoring or HTTP process exited (status %s).\n' "$status" >&2
exit 1
