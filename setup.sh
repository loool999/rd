#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VNC_DIR="${SCRIPT_DIR}/vnc"
CONF_DIR="${VNC_DIR}/config"

echo "============================================"
echo "  Linux Desktop — Setup"
echo "============================================"

# ── 1. noVNC web client ─────────────────────────────────────────────────────
echo "[1/4] noVNC..."
mkdir -p "${VNC_DIR}"
[ ! -d "${VNC_DIR}/noVNC" ] && \
    git clone --depth 1 https://github.com/novnc/noVNC.git "${VNC_DIR}/noVNC"

# ── 2. index.html (login + cursor overlay) ──────────────────────────────────
echo "[2/4] Writing index.html..."
cat > "${VNC_DIR}/noVNC/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Linux Desktop</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0f0f1a;font-family:'Segoe UI',Ubuntu,system-ui,sans-serif;
     color:#e0e0e0;overflow:hidden;height:100vh}

/* ── LOGIN ──────────────────────────────────────────────── */
#login{
  display:flex;align-items:center;justify-content:center;
  height:100vh;
  background:linear-gradient(135deg,#0f0f1a 0%,#1a1a2e 40%,#16213e 100%)
}
.lcard{
  background:rgba(255,255,255,.04);
  backdrop-filter:blur(20px);
  border:1px solid rgba(255,255,255,.08);
  border-radius:20px;padding:48px 44px;
  width:400px;max-width:90vw;
  box-shadow:0 20px 60px rgba(0,0,0,.5);
  text-align:center;
  animation:fadeUp .5s ease
}
@keyframes fadeUp{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
.lcard h1{font-size:32px;margin-bottom:6px}
.lcard .em{font-size:56px;display:block;margin-bottom:14px}
.lcard p{color:#999;font-size:14px;margin-bottom:24px;line-height:1.5}
.lcard input{
  width:100%;padding:14px 18px;
  border:1px solid rgba(255,255,255,.12);border-radius:12px;
  font-size:16px;background:rgba(255,255,255,.06);color:#fff;
  outline:none;transition:border-color .2s;margin-bottom:14px
}
.lcard input:focus{border-color:rgba(77,150,255,.6)}
.lcard input::placeholder{color:#555}
.lcard button{
  width:100%;padding:14px;border:none;border-radius:12px;
  font-size:16px;font-weight:600;cursor:pointer;
  background:linear-gradient(135deg,#4d96ff,#6bcb77);
  color:#fff;transition:transform .1s,box-shadow .2s
}
.lcard button:hover{transform:translateY(-1px);box-shadow:0 8px 24px rgba(77,150,255,.3)}
.lcard .hint{font-size:11px;color:#555;margin-top:18px;line-height:1.6}

/* ── DESKTOP ────────────────────────────────────────────── */
#desktop{display:none;height:100vh;flex-direction:column}
#bar{
  background:linear-gradient(135deg,#16213e,#0f3460);
  padding:0 10px;height:36px;
  display:flex;align-items:center;justify-content:space-between;
  box-shadow:0 2px 8px rgba(0,0,0,.3);
  position:relative;z-index:200;flex-shrink:0;gap:8px
}
#bar .tit{font-weight:700;font-size:13px;white-space:nowrap}
#users-bar{display:flex;gap:4px;align-items:center;overflow-x:auto;
           flex:1;padding:0 6px;min-width:0}
.ubadge{
  display:inline-flex;align-items:center;gap:4px;
  padding:2px 8px;border-radius:10px;
  background:rgba(255,255,255,.07);font-size:11px;
  white-space:nowrap;flex-shrink:0;
  border:1px solid rgba(255,255,255,.06)
}
.ubadge .dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.ubadge.me{border-color:rgba(255,255,255,.2);background:rgba(255,255,255,.12)}
.ctrls{display:flex;gap:4px;align-items:center;flex-shrink:0}
.b{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);
   color:#ddd;padding:3px 9px;border-radius:6px;font-size:11px;cursor:pointer;white-space:nowrap}
.b:hover{background:rgba(255,255,255,.16)}
.st{padding:3px 8px;border-radius:10px;font-size:10px;font-weight:700;white-space:nowrap}
.st.on{background:#00b894;color:#fff}
.st.off{background:#e17055;color:#fff}
.st.warn{background:#fdcb6e;color:#333}

/* ── VIEWPORT ───────────────────────────────────────────── */
#viewport{position:relative;flex:1;overflow:hidden;background:#0f0f1a}
#screen{width:100%;height:100%;position:relative;z-index:1}

/* cursor overlay: MUST be above noVNC canvas */
#cursorlayer{
  position:absolute;
  top:0;left:0;right:0;bottom:0;
  pointer-events:none;
  z-index:9999;
  overflow:hidden
}

/* ── CURSORS ────────────────────────────────────────────── */
.rcursor{
  position:absolute;left:0;top:0;
  pointer-events:none;
  transition:transform 50ms linear,opacity .15s;
  z-index:10000;
  will-change:transform;
  filter:drop-shadow(1px 2px 3px rgba(0,0,0,.5))
}
.rcursor.gone{opacity:0}
.rcursor .cname{
  position:absolute;left:16px;top:16px;
  padding:2px 7px;border-radius:5px;
  font-size:10px;font-weight:700;color:#fff;
  white-space:nowrap;
  box-shadow:0 2px 6px rgba(0,0,0,.4)
}
/* self cursor: just a ring, not a full arrow */
.selfcursor{
  position:absolute;left:0;top:0;
  pointer-events:none;
  z-index:10001;
  will-change:transform;
  transition:transform 16ms linear,opacity .15s
}
.selfcursor.gone{opacity:0}
.selfcursor .ring{
  width:20px;height:20px;border-radius:50%;
  border:2.5px solid;
  margin-left:-10px;margin-top:-10px;
  opacity:.6;
  box-shadow:0 0 6px rgba(0,0,0,.3)
}
.selfcursor .sname{
  position:absolute;left:12px;top:8px;
  padding:1px 6px;border-radius:4px;
  font-size:9px;font-weight:600;color:#fff;
  white-space:nowrap;opacity:.7
}
</style>
</head>
<body>

<!-- ═════ LOGIN ═════ -->
<div id="login">
  <div class="lcard">
    <span class="em">🐧</span>
    <h1>Linux Desktop</h1>
    <p>Enter your name to join the shared desktop.<br>
       Everyone sees each other's cursor in real-time.</p>
    <input type="text" id="uname" placeholder="Your name" maxlength="20"
           autofocus autocomplete="off" spellcheck="false">
    <button id="gobtn">Connect</button>
    <div class="hint">
      Open this link in multiple tabs or share it<br>
      with others to see all cursors live.
    </div>
  </div>
</div>

<!-- ═════ DESKTOP ═════ -->
<div id="desktop">
  <div id="bar">
    <span class="tit">🐧 Desktop</span>
    <div id="users-bar"></div>
    <div class="ctrls">
      <button class="b" id="fitbtn">⛶ Fit</button>
      <button class="b" id="cadbtn">⌨ C-A-D</button>
      <button class="b" id="pastebtn">📋 Paste</button>
      <span id="vncst" class="st off">VNC …</span>
      <span id="csst" class="st off">Cursors …</span>
    </div>
  </div>
  <div id="viewport">
    <div id="screen"></div>
    <div id="cursorlayer"></div>
  </div>
</div>

<script type="module">
import RFB from './core/rfb.js';

/* ── state ─────────────────────────────────────────────── */
let rfb = null, cursorWs = null;
let myName = '', myColor = '#4d96ff';
const remoteCursors = {};   // username → {el, x, y, color, visible}
let selfEl = null;          // own cursor element
let reconnTimer = null;
const HZ = 30;
let lastSend = 0;

/* ── DOM ───────────────────────────────────────────────── */
const $login   = document.getElementById('login');
const $desktop = document.getElementById('desktop');
const $uname   = document.getElementById('uname');
const $screen  = document.getElementById('screen');
const $vp      = document.getElementById('viewport');
const $cl      = document.getElementById('cursorlayer');
const $ub      = document.getElementById('users-bar');
const $vncst   = document.getElementById('vncst');
const $csst    = document.getElementById('csst');

/* ── login ─────────────────────────────────────────────── */
document.getElementById('gobtn').onclick = go;
$uname.onkeydown = e => { if(e.key==='Enter') go(); };

function go(){
  myName = $uname.value.trim();
  if(!myName){ $uname.focus(); return; }
  $login.style.display = 'none';
  $desktop.style.display = 'flex';
  startVNC();
  startCursors();
  trackMouse();
}

/* ── VNC ───────────────────────────────────────────────── */
function startVNC(){
  const s = location.protocol==='https:'?'wss':'ws';
  const url = `${s}://${location.host}/websockify`;
  rfb = new RFB($screen, url, {
    scaleViewport:true, resizeSession:true, clipViewport:false
  });
  rfb.background='#0f0f1a';
  rfb.qualityLevel=8;
  rfb.compressionLevel=2;
  rfb.addEventListener('connect',()=>{
    $vncst.textContent='VNC ✓'; $vncst.className='st on'; rfb.focus();
  });
  rfb.addEventListener('disconnect',e=>{
    $vncst.textContent=e.detail.clean?'VNC ✗':'VNC lost'; $vncst.className='st off';
  });
  rfb.addEventListener('credentialsrequired',()=>rfb.sendCredentials({password:''}));
  rfb.addEventListener('clipboard',e=>{
    navigator.clipboard?.writeText(e.detail.text).catch(()=>{});
  });
  document.getElementById('fitbtn').onclick=()=>{ if(rfb) rfb.scaleViewport=!rfb.scaleViewport; };
  document.getElementById('cadbtn').onclick=()=>{ if(rfb) rfb.sendCtrlAltDel(); };
  document.getElementById('pastebtn').onclick=()=>{
    navigator.clipboard?.readText().then(t=>{ if(t&&rfb) rfb.clipboardPasteFrom(t); }).catch(()=>{});
  };
  document.addEventListener('paste',e=>{
    const t=e.clipboardData?.getData('text'); if(t&&rfb) rfb.clipboardPasteFrom(t);
  });
}

/* ── CURSOR WS — same origin, same port! ─────────────── */
function startCursors(){
  if(reconnTimer){ clearTimeout(reconnTimer); reconnTimer=null; }
  const s = location.protocol==='https:'?'wss':'ws';
  const url = `${s}://${location.host}/cursors`;
  try{ cursorWs = new WebSocket(url); } catch(e){ schedReconn(); return; }

  cursorWs.onopen = ()=>{
    $csst.textContent='Cursors ✓'; $csst.className='st on';
    cursorWs.send(JSON.stringify({type:'join',username:myName}));
  };
  cursorWs.onmessage = e=>{
    let d; try{ d=JSON.parse(e.data); }catch{ return; }
    if(d.type==='welcome'){
      myColor = d.color;
      createSelfCursor();
    } else if(d.type==='users'){
      renderUsers(d.users);
    } else if(d.type==='cursor'){
      renderRemote(d);
    } else if(d.type==='left'){
      removeRemote(d.username);
    }
  };
  cursorWs.onclose = ()=>{
    $csst.textContent='Cursors ✗'; $csst.className='st off';
    schedReconn();
  };
  cursorWs.onerror = ()=>{};
}

function schedReconn(){
  if(reconnTimer) return;
  reconnTimer = setTimeout(()=>{ reconnTimer=null; startCursors(); }, 2000);
}

/* ── mouse tracking ──────────────────────────────────── */
function trackMouse(){
  // Use CAPTURE phase so we get events even if noVNC canvas eats them
  $vp.addEventListener('mousemove', e=>{
    const r = $vp.getBoundingClientRect();
    const nx = (e.clientX - r.left) / r.width;
    const ny = (e.clientY - r.top) / r.height;
    const px = e.clientX - r.left;
    const py = e.clientY - r.top;

    // Update self cursor immediately (local, no latency)
    if(selfEl){
      selfEl.style.transform = `translate(${px}px,${py}px)`;
      selfEl.classList.remove('gone');
    }

    // Throttle network sends
    const now = performance.now();
    if(now - lastSend < 1000/HZ) return;
    lastSend = now;
    if(cursorWs?.readyState===1){
      cursorWs.send(JSON.stringify({type:'move',x:nx,y:ny,visible:true}));
    }
  }, true);  // ← capture phase

  $vp.addEventListener('mouseleave',()=>{
    if(selfEl) selfEl.classList.add('gone');
    if(cursorWs?.readyState===1){
      cursorWs.send(JSON.stringify({type:'move',x:-1,y:-1,visible:false}));
    }
  }, true);
}

/* ── self cursor (colored ring, proves overlay works) ── */
function createSelfCursor(){
  if(selfEl) selfEl.remove();
  selfEl = document.createElement('div');
  selfEl.className = 'selfcursor gone';
  selfEl.innerHTML =
    `<div class="ring" style="border-color:${myColor}"></div>`+
    `<span class="sname" style="background:${myColor}">${esc(myName)}</span>`;
  $cl.appendChild(selfEl);
}

/* ── user badges ─────────────────────────────────────── */
function renderUsers(users){
  $ub.innerHTML='';
  for(const u of users){
    const b = document.createElement('span');
    b.className = 'ubadge' + (u.username===myName?' me':'');
    b.innerHTML = `<span class="dot" style="background:${u.color}"></span>${esc(u.username)}`;
    $ub.appendChild(b);
  }
}

/* ── remote cursor rendering ─────────────────────────── */
function arrowSVG(color){
  return `<svg width="20" height="24" viewBox="0 0 20 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <path d="M1,1 L1,19 L5.5,14 L9.5,23 L12.5,21.5 L8.5,13 L14,13 Z"
          fill="${color}" stroke="#ffffff" stroke-width="1.4" stroke-linejoin="round"/>
  </svg>`;
}

function renderRemote(d){
  let c = remoteCursors[d.username];

  if(!c){
    const el = document.createElement('div');
    el.className = 'rcursor gone';
    el.innerHTML = arrowSVG(d.color) +
      `<span class="cname" style="background:${d.color}">${esc(d.username)}</span>`;
    $cl.appendChild(el);
    c = {el, x:0, y:0, color:d.color, visible:false};
    remoteCursors[d.username] = c;
  }

  c.x = d.x;
  c.y = d.y;
  c.visible = d.visible;

  if(!d.visible || d.x<0 || d.y<0){
    c.el.classList.add('gone');
  } else {
    c.el.classList.remove('gone');
    const r = $vp.getBoundingClientRect();
    c.el.style.transform = `translate(${d.x*r.width}px,${d.y*r.height}px)`;
  }
}

function removeRemote(username){
  const c = remoteCursors[username];
  if(c){ c.el.remove(); delete remoteCursors[username]; }
}

/* ── recalc on resize ────────────────────────────────── */
window.addEventListener('resize',()=>{
  const r = $vp.getBoundingClientRect();
  for(const c of Object.values(remoteCursors)){
    if(c.visible && c.x>=0)
      c.el.style.transform = `translate(${c.x*r.width}px,${c.y*r.height}px)`;
  }
});

/* ── util ─────────────────────────────────────────────── */
function esc(s){ const d=document.createElement('span'); d.textContent=s; return d.innerHTML; }
</script>
</body>
</html>
HTMLEOF

# ── 3. Wallpaper ─────────────────────────────────────────────────────────────
echo "[3/4] Wallpaper..."
mkdir -p "${CONF_DIR}/wallpaper"
WPFILE="${CONF_DIR}/wallpaper/wallpaper.png"
if [ ! -f "${WPFILE}" ]; then
    convert -size 1920x1080 xc:'#1a1a2e' \
        -fill '#0f3460' -draw "rectangle 0,0 1920,540" \
        -blur 0x80 \
        -fill 'rgba(83,52,131,0.25)' -draw "circle 600,400 600,700" \
        -blur 0x60 \
        "${WPFILE}" 2>/dev/null || \
    convert -size 1920x1080 gradient:'#1a1a2e'-'#0f3460' \
        "${WPFILE}" 2>/dev/null || \
    convert -size 1920x1080 xc:'#2d3436' "${WPFILE}" 2>/dev/null || true
fi

# ── 4. XFCE configs ─────────────────────────────────────────────────────────
echo "[4/4] XFCE configs..."
XFCE="${CONF_DIR}/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "${XFCE}" "${CONF_DIR}/xfce4/terminal" "${CONF_DIR}/desktop-files"

cat > "${XFCE}/xfce4-session.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSessionName" type="string" value="Failsafe"/>
    <property name="SessionName" type="string" value="Default"/>
    <property name="SaveOnExit" type="bool" value="false"/>
  </property>
  <property name="sessions" type="empty">
    <property name="Failsafe" type="empty">
      <property name="IsFailsafe" type="bool" value="true"/>
      <property name="Count" type="int" value="4"/>
      <property name="Client0_Command" type="array"><value type="string" value="xfwm4"/></property>
      <property name="Client0_Priority" type="int" value="15"/>
      <property name="Client0_PerScreen" type="bool" value="false"/>
      <property name="Client1_Command" type="array"><value type="string" value="xfsettingsd"/></property>
      <property name="Client1_Priority" type="int" value="20"/>
      <property name="Client1_PerScreen" type="bool" value="false"/>
      <property name="Client2_Command" type="array"><value type="string" value="xfce4-panel"/></property>
      <property name="Client2_Priority" type="int" value="25"/>
      <property name="Client2_PerScreen" type="bool" value="false"/>
      <property name="Client3_Command" type="array"><value type="string" value="xfdesktop"/></property>
      <property name="Client3_Priority" type="int" value="25"/>
      <property name="Client3_PerScreen" type="bool" value="false"/>
    </property>
  </property>
</channel>
EOF

cat > "${XFCE}/xfce4-panel.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="22"/>
      <property name="size" type="uint" value="36"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/>
        <value type="int" value="3"/><value type="int" value="4"/>
        <value type="int" value="5"/><value type="int" value="6"/>
        <value type="int" value="7"/><value type="int" value="8"/>
        <value type="int" value="9"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="button-title" type="string" value=" Applications"/>
      <property name="show-button-title" type="bool" value="true"/>
    </property>
    <property name="plugin-2" type="string" value="separator"><property name="style" type="uint" value="3"/></property>
    <property name="plugin-3" type="string" value="launcher"><property name="items" type="array"><value type="string" value="thunar.desktop"/></property></property>
    <property name="plugin-4" type="string" value="launcher"><property name="items" type="array"><value type="string" value="xfce4-terminal-emulator.desktop"/></property></property>
    <property name="plugin-5" type="string" value="launcher"><property name="items" type="array"><value type="string" value="firefox.desktop"/></property></property>
    <property name="plugin-6" type="string" value="tasklist"><property name="grouping" type="uint" value="1"/><property name="show-labels" type="bool" value="true"/><property name="flat-buttons" type="bool" value="true"/></property>
    <property name="plugin-7" type="string" value="separator"><property name="expand" type="bool" value="true"/><property name="style" type="uint" value="0"/></property>
    <property name="plugin-8" type="string" value="systray"><property name="square-icons" type="bool" value="true"/></property>
    <property name="plugin-9" type="string" value="clock"><property name="digital-format" type="string" value="%a %b %d  %H:%M"/><property name="mode" type="uint" value="2"/></property>
  </property>
</channel>
EOF

cat > "${XFCE}/xfwm4.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
    <property name="title_font" type="string" value="Ubuntu Bold 10"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="snap_to_windows" type="bool" value="true"/>
    <property name="tile_on_move" type="bool" value="true"/>
  </property>
</channel>
EOF

cat > "${XFCE}/xsettings.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="CursorThemeName" type="string" value="breeze_cursors"/>
    <property name="CursorSize" type="int" value="24"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Ubuntu 10"/>
    <property name="MonospaceFontName" type="string" value="Fira Code 10"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
    <property name="DPI" type="int" value="96"/>
  </property>
</channel>
EOF

cat > "${XFCE}/xfce4-desktop.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="2"/>
    <property name="icon-size" type="uint" value="48"/>
    <property name="file-icons" type="empty">
      <property name="show-home" type="bool" value="true"/>
      <property name="show-filesystem" type="bool" value="true"/>
      <property name="show-trash" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF

cat > "${XFCE}/keyboard-layout.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="keyboard-layout" version="1.0">
  <property name="Default" type="empty">
    <property name="XkbDisable" type="bool" value="true"/>
  </property>
</channel>
EOF

cat > "${CONF_DIR}/xfce4/terminal/terminalrc" << 'EOF'
[Configuration]
FontName=Fira Code 11
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=TRUE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=110x30
MiscMenubarDefault=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscHighlightUrls=TRUE
MiscShowUnsafePasteDialog=FALSE
ScrollingOnOutput=FALSE
ColorForeground=#cdd6f4
ColorBackground=#1e1e2e
ColorCursor=#f5e0dc
ColorSelection=#45475a
ColorSelectionUseDefault=FALSE
ColorBoldIsBright=TRUE
ColorPalette=#45475a;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#bac2de;#585b70;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#a6adc8
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.92
EOF

for name in terminal files firefox text-editor writer calc calculator sysmonitor; do
case $name in
  terminal)    E="xfce4-terminal"         I="utilities-terminal"       N="Terminal";;
  files)       E="thunar"                 I="system-file-manager"      N="Files";;
  firefox)     E="firefox --no-remote"    I="firefox"                  N="Firefox";;
  text-editor) E="mousepad"              I="accessories-text-editor"  N="Text Editor";;
  writer)      E="libreoffice --writer"  I="libreoffice-writer"       N="Writer";;
  calc)        E="libreoffice --calc"    I="libreoffice-calc"         N="Calc";;
  calculator)  E="gnome-calculator"      I="accessories-calculator"   N="Calculator";;
  sysmonitor)  E="gnome-system-monitor"  I="utilities-system-monitor" N="System Monitor";;
esac
cat > "${CONF_DIR}/desktop-files/${name}.desktop" << DEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${N}
Exec=${E}
Icon=${I}
Terminal=false
DEOF
done

echo ""
echo "✅  Setup complete!   Run:  bash start.sh"