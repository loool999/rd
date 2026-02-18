#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VNC_DIR="${SCRIPT_DIR}/vnc"
CONF_DIR="${VNC_DIR}/config"
LOG_DIR="${VNC_DIR}/logs"
PID_FILE="${VNC_DIR}/.pids"

DISPLAY_NUM=1
RESOLUTION="1920x1080x24"
VNC_PORT=5901
SERVER_PORT=6080

export DISPLAY=":${DISPLAY_NUM}"
export LANG="en_US.UTF-8"
export NO_AT_BRIDGE=1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE

mkdir -p "${LOG_DIR}"

# ── Pre-flight ───────────────────────────────────────────────────────────────
if [ ! -d "${VNC_DIR}/noVNC" ]; then echo "ERROR: Run setup.sh first."; exit 1; fi
if [ -f "${PID_FILE}" ]; then bash "${SCRIPT_DIR}/stop.sh" 2>/dev/null || true; sleep 1; fi
rm -f  "/tmp/.X${DISPLAY_NUM}-lock"     2>/dev/null || true
rm -rf "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

# ── Copy XFCE configs ───────────────────────────────────────────────────────
echo "Preparing desktop..."
XFCE_DST="${HOME}/.config/xfce4"
mkdir -p "${XFCE_DST}/xfconf/xfce-perchannel-xml" "${XFCE_DST}/terminal"
cp -n "${CONF_DIR}/xfce4/xfconf/xfce-perchannel-xml/"*.xml \
      "${XFCE_DST}/xfconf/xfce-perchannel-xml/" 2>/dev/null || true
cp -n "${CONF_DIR}/xfce4/terminal/terminalrc" \
      "${XFCE_DST}/terminal/terminalrc" 2>/dev/null || true

mkdir -p "${HOME}/.config/gtk-3.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=breeze_cursors
gtk-cursor-theme-size=24
gtk-font-name=Ubuntu 10
gtk-application-prefer-dark-theme=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF
cat > "${HOME}/.gtkrc-2.0" << 'EOF'
gtk-theme-name="Arc-Dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Ubuntu 10"
EOF

mkdir -p "${HOME}/Desktop" "${HOME}/Documents" "${HOME}/Downloads" \
         "${HOME}/Music" "${HOME}/Pictures" "${HOME}/Videos"
mkdir -p "${HOME}/.config"
cat > "${HOME}/.config/user-dirs.dirs" << EOF
XDG_DESKTOP_DIR="${HOME}/Desktop"
XDG_DOWNLOAD_DIR="${HOME}/Downloads"
XDG_DOCUMENTS_DIR="${HOME}/Documents"
XDG_MUSIC_DIR="${HOME}/Music"
XDG_PICTURES_DIR="${HOME}/Pictures"
XDG_VIDEOS_DIR="${HOME}/Videos"
XDG_TEMPLATES_DIR="${HOME}/Templates"
XDG_PUBLICSHARE_DIR="${HOME}/Public"
EOF

cp -f "${CONF_DIR}/desktop-files/"*.desktop "${HOME}/Desktop/" 2>/dev/null || true
chmod +x "${HOME}/Desktop/"*.desktop 2>/dev/null || true
for f in "${HOME}/Desktop/"*.desktop; do
    [ -f "$f" ] && gio set "$f" metadata::xfce-exe-checksum \
        "$(sha256sum "$f" | awk '{print $1}')" 2>/dev/null || true
done
ln -sf "${SCRIPT_DIR}" "${HOME}/Desktop/Workspace" 2>/dev/null || true

echo "============================================"
echo "  Starting Linux Desktop"
echo "============================================"

# ── 1. Xvfb ─────────────────────────────────────────────────────────────────
echo "[1/5] Xvfb..."
Xvfb ":${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" \
    -ac +extension GLX +extension RANDR +render \
    -nolisten tcp -dpi 96 \
    > "${LOG_DIR}/xvfb.log" 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 50); do
    xdpyinfo -display ":${DISPLAY_NUM}" >/dev/null 2>&1 && break; sleep 0.2
done
if ! xdpyinfo -display ":${DISPLAY_NUM}" >/dev/null 2>&1; then
    echo "FATAL: Xvfb failed"; cat "${LOG_DIR}/xvfb.log"; exit 1
fi
echo "  ✓ Xvfb  PID ${XVFB_PID}"

# ── 2. D-Bus ────────────────────────────────────────────────────────────────
echo "[2/5] D-Bus..."
eval "$(dbus-launch --sh-syntax 2>/dev/null)" || true
export DBUS_SESSION_BUS_ADDRESS
echo "  ✓ D-Bus"

# ── 3. XFCE ─────────────────────────────────────────────────────────────────
echo "[3/5] XFCE..."
xfsettingsd --display=":${DISPLAY_NUM}" > "${LOG_DIR}/xfsettingsd.log" 2>&1 &
sleep 1
xfwm4 --display=":${DISPLAY_NUM}" --compositor=off > "${LOG_DIR}/xfwm4.log" 2>&1 &
XFWM4_PID=$!; sleep 0.5
xfdesktop --display=":${DISPLAY_NUM}" > "${LOG_DIR}/xfdesktop.log" 2>&1 &
DESKTOP_PID=$!; sleep 0.5
xfce4-panel --display=":${DISPLAY_NUM}" > "${LOG_DIR}/xfce4-panel.log" 2>&1 &
PANEL_PID=$!; sleep 1
thunar --daemon > "${LOG_DIR}/thunar.log" 2>&1 &
echo "  ✓ XFCE  WM:${XFWM4_PID} Desktop:${DESKTOP_PID} Panel:${PANEL_PID}"

# ── wallpaper ────────────────────────────────────────────────────────────────
WPFILE="${CONF_DIR}/wallpaper/wallpaper.png"
if [ -f "${WPFILE}" ] && command -v xfconf-query &>/dev/null; then
    sleep 1
    MON=$(xrandr --display ":${DISPLAY_NUM}" 2>/dev/null | grep ' connected' | head -1 | awk '{print $1}')
    MON="${MON:-screen}"
    for ws in 0 1 2 3; do
        B="/backdrop/screen0/monitor${MON}/workspace${ws}"
        xfconf-query -c xfce4-desktop -p "${B}/last-image" -s "${WPFILE}" --create -t string 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "${B}/image-style" -s 5 --create -t int 2>/dev/null || true
    done
fi

# ── 4. x11vnc ───────────────────────────────────────────────────────────────
echo "[4/5] x11vnc on :${VNC_PORT}..."
x11vnc -display ":${DISPLAY_NUM}" -rfbport "${VNC_PORT}" \
    -nopw -shared -forever \
    -noxdamage -cursor arrow -xkb \
    -skip_lockkeys -nomodtweak \
    > "${LOG_DIR}/x11vnc.log" 2>&1 &
X11VNC_PID=$!
for _ in $(seq 1 30); do
    ss -tlnp 2>/dev/null | grep -q ":${VNC_PORT}" && break; sleep 0.3
done
echo "  ✓ x11vnc  PID ${X11VNC_PID}"

# ── 5. Combined server (noVNC + VNC proxy + cursors) ────────────────────────
echo "[5/5] Combined server on :${SERVER_PORT}..."
export VNC_PORT="${VNC_PORT}"
export NOVNC_PORT="${SERVER_PORT}"
export NOVNC_DIR="${VNC_DIR}/noVNC"
python3 "${SCRIPT_DIR}/server.py" \
    > "${LOG_DIR}/server.log" 2>&1 &
SERVER_PID=$!
echo "  ✓ Server  PID ${SERVER_PID}"

# ── Save PIDs ────────────────────────────────────────────────────────────────
cat > "${PID_FILE}" << EOF
XVFB_PID=${XVFB_PID}
XFWM4_PID=${XFWM4_PID}
DESKTOP_PID=${DESKTOP_PID}
PANEL_PID=${PANEL_PID}
X11VNC_PID=${X11VNC_PID}
SERVER_PID=${SERVER_PID}
DBUS_SESSION_BUS_PID=${DBUS_SESSION_BUS_PID:-}
EOF

# ── Open terminal ────────────────────────────────────────────────────────────
sleep 1
xfce4-terminal --display=":${DISPLAY_NUM}" \
    --working-directory="${SCRIPT_DIR}" \
    --title="Workspace" --geometry=100x28+100+100 \
    > "${LOG_DIR}/terminal.log" 2>&1 &

sleep 3

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
FAIL=0
for p in "Xvfb:${XVFB_PID}" "xfwm4:${XFWM4_PID}" "xfdesktop:${DESKTOP_PID}" \
         "panel:${PANEL_PID}" "x11vnc:${X11VNC_PID}" "server:${SERVER_PID}"; do
    n="${p%%:*}"; id="${p##*:}"
    if kill -0 "${id}" 2>/dev/null; then
        printf "  ✓ %-12s PID %s\n" "${n}" "${id}"
    else
        printf "  ✗ %-12s FAILED\n" "${n}"
        FAIL=1
    fi
done
[ "${FAIL}" -eq 1 ] && echo "Check: ${LOG_DIR}/" && exit 1

echo ""
echo "============================================"
echo "  ✅  Linux Desktop is running!"
echo ""
echo "  Open port ${SERVER_PORT} from the Ports tab"
echo ""
echo "  👁️  You'll see your own cursor as a"
echo "      colored ring on the desktop."
echo "  👥  Open a 2nd tab with the same URL"
echo "      to see multi-user cursors."
echo ""
echo "  bash stop.sh  — shut down"
echo "============================================"