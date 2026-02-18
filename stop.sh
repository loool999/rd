#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/vnc/.pids"

echo "Stopping Linux Desktop..."

if [ -f "${PID_FILE}" ]; then
    source "${PID_FILE}"
    for pair in \
        "server:${SERVER_PID:-}" \
        "x11vnc:${X11VNC_PID:-}" \
        "panel:${PANEL_PID:-}" \
        "xfdesktop:${DESKTOP_PID:-}" \
        "xfwm4:${XFWM4_PID:-}" \
        "Xvfb:${XVFB_PID:-}" \
        "dbus:${DBUS_SESSION_BUS_PID:-}"; do
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

pkill -f "server.py"        2>/dev/null || true
pkill -f "Xvfb :1"          2>/dev/null || true
pkill -f "x11vnc"           2>/dev/null || true
pkill -f "websockify"       2>/dev/null || true
pkill -f "xfwm4"            2>/dev/null || true
pkill -f "xfce4-panel"      2>/dev/null || true
pkill -f "xfdesktop"        2>/dev/null || true
pkill -f "xfsettingsd"      2>/dev/null || true
pkill -f "thunar.*daemon"   2>/dev/null || true
pkill -f "xfce4-terminal"   2>/dev/null || true
pkill -f "xfconfd"          2>/dev/null || true

rm -f  /tmp/.X1-lock        2>/dev/null || true
rm -rf /tmp/.X11-unix/X1    2>/dev/null || true

echo "Done."