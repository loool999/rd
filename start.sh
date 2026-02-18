#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VNC_DIR="${SCRIPT_DIR}/vnc"
CONF_DIR="${VNC_DIR}/config"
LOG_DIR="${VNC_DIR}/logs"
PID_FILE="${VNC_DIR}/.pids"
DESKTOP_HOME="/home/desktop"

DISPLAY_NUM=1
RESOLUTION="1920x1080x24"
VNC_PORT=5901
SERVER_PORT=6080

export DISPLAY=":${DISPLAY_NUM}"
export LANG="en_US.UTF-8"
export NO_AT_BRIDGE=1

mkdir -p "${LOG_DIR}"

# ── Pre-flight ───────────────────────────────────────────────────────────────
if [ ! -d "${VNC_DIR}/noVNC" ]; then echo "ERROR: Run setup.sh first."; exit 1; fi
if [ -f "${PID_FILE}" ]; then bash "${SCRIPT_DIR}/stop.sh" 2>/dev/null || true; sleep 1; fi
rm -f  "/tmp/.X${DISPLAY_NUM}-lock"     2>/dev/null || true
rm -rf "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

# ── Protect workspace files from desktop user ────────────────────────────────
echo "Locking down workspace..."
chown root:root "${SCRIPT_DIR}/server.py" "${SCRIPT_DIR}/start.sh" \
                "${SCRIPT_DIR}/stop.sh"   "${SCRIPT_DIR}/setup.sh" 2>/dev/null || true
chmod 755 "${SCRIPT_DIR}/server.py" "${SCRIPT_DIR}/start.sh" \
          "${SCRIPT_DIR}/stop.sh"   "${SCRIPT_DIR}/setup.sh" 2>/dev/null || true
chown -R root:root "${VNC_DIR}" 2>/dev/null || true
chown -R root:root "${SCRIPT_DIR}/.devcontainer" 2>/dev/null || true

# ── Prepare desktop user's home ─────────────────────────────────────────────
echo "Preparing desktop user home..."
XFCE_DST="${DESKTOP_HOME}/.config/xfce4"
mkdir -p "${XFCE_DST}/xfconf/xfce-perchannel-xml" "${XFCE_DST}/terminal"
cp -f "${CONF_DIR}/xfce4/xfconf/xfce-perchannel-xml/"*.xml \
      "${XFCE_DST}/xfconf/xfce-perchannel-xml/" 2>/dev/null || true
cp -f "${CONF_DIR}/xfce4/terminal/terminalrc" \
      "${XFCE_DST}/terminal/terminalrc" 2>/dev/null || true

mkdir -p "${DESKTOP_HOME}/.config/gtk-3.0"
cat > "${DESKTOP_HOME}/.config/gtk-3.0/settings.ini" << 'EOF'
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
cat > "${DESKTOP_HOME}/.gtkrc-2.0" << 'EOF'
gtk-theme-name="Arc-Dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Ubuntu 10"
EOF

mkdir -p "${DESKTOP_HOME}/Desktop" "${DESKTOP_HOME}/Documents" \
         "${DESKTOP_HOME}/Downloads" "${DESKTOP_HOME}/Music" \
         "${DESKTOP_HOME}/Pictures" "${DESKTOP_HOME}/Videos"
mkdir -p "${DESKTOP_HOME}/.config"
cat > "${DESKTOP_HOME}/.config/user-dirs.dirs" << EOF
XDG_DESKTOP_DIR="${DESKTOP_HOME}/Desktop"
XDG_DOWNLOAD_DIR="${DESKTOP_HOME}/Downloads"
XDG_DOCUMENTS_DIR="${DESKTOP_HOME}/Documents"
XDG_MUSIC_DIR="${DESKTOP_HOME}/Music"
XDG_PICTURES_DIR="${DESKTOP_HOME}/Pictures"
XDG_VIDEOS_DIR="${DESKTOP_HOME}/Videos"
XDG_TEMPLATES_DIR="${DESKTOP_HOME}/Templates"
XDG_PUBLICSHARE_DIR="${DESKTOP_HOME}/Public"
EOF

# Desktop shortcuts
cp -f "${CONF_DIR}/desktop-files/"*.desktop "${DESKTOP_HOME}/Desktop/" 2>/dev/null || true
chmod +x "${DESKTOP_HOME}/Desktop/"*.desktop 2>/dev/null || true

# Workspace link on desktop (read-only for desktop user)
ln -sf "${SCRIPT_DIR}" "${DESKTOP_HOME}/Desktop/Workspace" 2>/dev/null || true

# Fix ownership: desktop user owns their home EXCEPT .bashrc/.profile (root-owned, immutable)
chown -R desktop:desktop "${DESKTOP_HOME}" 2>/dev/null || true
chown root:root "${DESKTOP_HOME}/.bashrc" "${DESKTOP_HOME}/.profile" 2>/dev/null || true
chmod 644 "${DESKTOP_HOME}/.bashrc" "${DESKTOP_HOME}/.profile" 2>/dev/null || true
chattr +i "${DESKTOP_HOME}/.bashrc" 2>/dev/null || true
chattr +i "${DESKTOP_HOME}/.profile" 2>/dev/null || true

echo "============================================"
echo "  Starting Secured Linux Desktop"
echo "============================================"

# ── 1. Xvfb (as root) ───────────────────────────────────────────────────────
echo "[1/6] Xvfb..."
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

# ── 2. Allow desktop user to use the X display ──────────────────────────────
echo "[2/6] X11 auth..."
xhost +SI:localuser:desktop > /dev/null 2>&1
echo "  ✓ xhost granted to desktop user"

# ── 3. D-Bus + XFCE (as desktop user) ───────────────────────────────────────
echo "[3/6] XFCE as 'desktop' user..."

# Start XFCE components as the desktop user via runuser
runuser -l desktop -c "
    export DISPLAY=:${DISPLAY_NUM}
    export LANG=en_US.UTF-8
    export NO_AT_BRIDGE=1
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=XFCE

    eval \"\$(dbus-launch --sh-syntax 2>/dev/null)\" || true

    xfsettingsd --display=:${DISPLAY_NUM} &
    sleep 1
    xfwm4 --display=:${DISPLAY_NUM} --compositor=off &
    sleep 0.5
    xfdesktop --display=:${DISPLAY_NUM} &
    sleep 0.5
    xfce4-panel --display=:${DISPLAY_NUM} &
    sleep 0.5
    thunar --daemon &
" > "${LOG_DIR}/xfce.log" 2>&1 &
XFCE_PID=$!
sleep 4
echo "  ✓ XFCE running as 'desktop'"

# Set wallpaper
WPFILE="${CONF_DIR}/wallpaper/wallpaper.png"
if [ -f "${WPFILE}" ]; then
    MON=$(xrandr --display ":${DISPLAY_NUM}" 2>/dev/null | grep ' connected' | head -1 | awk '{print $1}')
    MON="${MON:-screen}"
    for ws in 0 1 2 3; do
        B="/backdrop/screen0/monitor${MON}/workspace${ws}"
        runuser -l desktop -c "
            export DISPLAY=:${DISPLAY_NUM}
            xfconf-query -c xfce4-desktop -p '${B}/last-image' -s '${WPFILE}' --create -t string
            xfconf-query -c xfce4-desktop -p '${B}/image-style' -s 5 --create -t int
        " 2>/dev/null || true
    done
fi

# ── 4. x11vnc (as root — desktop user can't kill it) ────────────────────────
echo "[4/6] x11vnc..."
x11vnc -display ":${DISPLAY_NUM}" -rfbport "${VNC_PORT}" \
    -nopw -shared -forever \
    -noxdamage -cursor arrow -xkb \
    -skip_lockkeys -nomodtweak \
    > "${LOG_DIR}/x11vnc.log" 2>&1 &
X11VNC_PID=$!
for _ in $(seq 1 30); do
    ss -tlnp 2>/dev/null | grep -q ":${VNC_PORT}" && break; sleep 0.3
done
echo "  ✓ x11vnc  PID ${X11VNC_PID}  (root-owned, unkillable by desktop)"

# ── 5. Combined server (as root) ────────────────────────────────────────────
echo "[5/6] Server on :${SERVER_PORT}..."
export VNC_PORT="${VNC_PORT}"
export NOVNC_PORT="${SERVER_PORT}"
export NOVNC_DIR="${VNC_DIR}/noVNC"
python3 "${SCRIPT_DIR}/server.py" \
    > "${LOG_DIR}/server.log" 2>&1 &
SERVER_PID=$!
echo "  ✓ Server  PID ${SERVER_PID}  (root-owned, unkillable by desktop)"

# ── 6. Watchdog: auto-restart XFCE if it crashes ────────────────────────────
echo "[6/6] Watchdog..."
(
    while true; do
        sleep 15
        # Check if XFCE components are alive for the desktop user
        if ! pgrep -u desktop xfwm4 > /dev/null 2>&1; then
            echo "[watchdog] xfwm4 died, restarting..." >> "${LOG_DIR}/watchdog.log"
            runuser -l desktop -c "DISPLAY=:${DISPLAY_NUM} xfwm4 --compositor=off &" 2>/dev/null
        fi
        if ! pgrep -u desktop xfdesktop > /dev/null 2>&1; then
            echo "[watchdog] xfdesktop died, restarting..." >> "${LOG_DIR}/watchdog.log"
            runuser -l desktop -c "DISPLAY=:${DISPLAY_NUM} xfdesktop &" 2>/dev/null
        fi
        if ! pgrep -u desktop xfce4-panel > /dev/null 2>&1; then
            echo "[watchdog] xfce4-panel died, restarting..." >> "${LOG_DIR}/watchdog.log"
            runuser -l desktop -c "DISPLAY=:${DISPLAY_NUM} xfce4-panel &" 2>/dev/null
        fi
    done
) > "${LOG_DIR}/watchdog.log" 2>&1 &
WATCHDOG_PID=$!
echo "  ✓ Watchdog  PID ${WATCHDOG_PID}"

# ── Save PIDs ────────────────────────────────────────────────────────────────
cat > "${PID_FILE}" << EOF
XVFB_PID=${XVFB_PID}
X11VNC_PID=${X11VNC_PID}
SERVER_PID=${SERVER_PID}
WATCHDOG_PID=${WATCHDOG_PID}
XFCE_PID=${XFCE_PID}
EOF
chmod 600 "${PID_FILE}"  # Only root can read the PID file

# Open a terminal on the desktop
sleep 1
runuser -l desktop -c "
    DISPLAY=:${DISPLAY_NUM} xfce4-terminal \
        --working-directory=${DESKTOP_HOME} \
        --title='Terminal' \
        --geometry=100x28+100+100 &
" > "${LOG_DIR}/terminal.log" 2>&1

sleep 2

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
FAIL=0
for p in "Xvfb:${XVFB_PID}" "x11vnc:${X11VNC_PID}" "server:${SERVER_PID}" "watchdog:${WATCHDOG_PID}"; do
    n="${p%%:*}"; id="${p##*:}"
    if kill -0 "${id}" 2>/dev/null; then
        printf "  ✓ %-12s PID %-8s (root)\n" "${n}" "${id}"
    else
        printf "  ✗ %-12s FAILED\n" "${n}"
        FAIL=1
    fi
done
# Check desktop user processes
for proc in xfwm4 xfdesktop xfce4-panel; do
    if pgrep -u desktop "${proc}" > /dev/null 2>&1; then
        printf "  ✓ %-12s (desktop user)\n" "${proc}"
    else
        printf "  ⚠ %-12s not detected yet\n" "${proc}"
    fi
done

[ "${FAIL}" -eq 1 ] && echo "Check: ${LOG_DIR}/" && exit 1

echo ""
echo "============================================"
echo "  ✅  Secured Linux Desktop is running!"
echo ""
echo "  Open port ${SERVER_PORT} from the Ports tab"
echo ""
echo "  🔒  Security:"
echo "      • Desktop runs as 'desktop' user (no sudo)"
echo "      • VNC/server run as root (unkillable)"
echo "      • rm -rf on system paths → blocked"
echo "      • shutdown/reboot/halt → blocked"
echo "      • kill/pkill on infrastructure → blocked"
echo "      • Workspace scripts → read-only"
echo "      • .bashrc → immutable (root-owned)"
echo "      • Watchdog auto-restarts XFCE if killed"
echo ""
echo "  bash stop.sh  