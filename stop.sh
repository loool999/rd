#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/vnc/.pids"

echo "Stopping Linux Desktop..."

if [ -f "${PID_FILE}" ]; then
    source "${PID_FILE}"
    for pair in \
        "watchdog:${WATCHDOG_PID:-}" \
        "server:${SERVER_PID:-}" \
        "x11vnc:${X11VNC_PID:-}" \
        "xfce:${XFCE_PID:-}" \
        "Xvfb:${XVFB_PID:-}"; do
        n="${pair%%:*}"; p="${pair##*:}"
        if [ -n "${p}" ] && kill -0 "${p}" 2>/dev/null; then
            kill "${p}" 2>/dev/null || true
            for _ in $(seq 1 15); do
                kill -0 "${p}" 2>/dev/null || break; sleep 0.2
            done
            kill -0 "${p}" 2>/dev/null && kill -9 "${p}" 2>/dev/null || true
            echo "  ✓ ${n} stopped"
        else
            echo "  - ${n} not running"
        fi
    done
    rm -f "${PID_FILE}"
else
    echo "  No PID file — sweeping..."
fi

# Kill all desktop user processes
pkill -u desktop 2>/dev/null || true
sleep 1
pkill -9 -u desktop 2>/dev/null || true

# Sweep infrastructure
pkill -f "server.py"        2>/dev/null || true
pkill -f "Xvfb :1"          2>/dev/null || true
pkill -f "x11vnc"           2>/dev/null || true
pkill -f "websockify"       2>/dev/null || true

rm -f  /tmp/.X1-lock        2>/dev/null || true
rm -rf /tmp/.X11-unix/X1    2>/dev/null || true

echo "Done."