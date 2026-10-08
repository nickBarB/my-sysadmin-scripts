#!/usr/bin/env bash
set -euo pipefail

INTERVAL=10
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/monitor.log}"

while true; do
    {
        printf '\n--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"

        printf '\nОперативная память:\n'
        free -h

        printf '\nДисковое пространство:\n'
        df -h

        printf '\nВремя работы и нагрузка:\n'
        uptime
    } >> "$LOG_FILE"

    sleep "$INTERVAL"
done
