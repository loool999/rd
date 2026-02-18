#!/usr/bin/env python3
"""
Single combined server (one port):
  /             → noVNC static files (index.html, core/rfb.js, etc.)
  /websockify   → WebSocket proxy to VNC server (x11vnc on localhost:5901)
  /cursors      → WebSocket for multi-user cursor sharing
"""

import asyncio
import json
import mimetypes
import os
import sys

from aiohttp import web, WSMsgType

# ── Config ───────────────────────────────────────────────────────────────────
VNC_HOST = "localhost"
VNC_PORT = int(os.environ.get("VNC_PORT", 5901))
LISTEN_PORT = int(os.environ.get("NOVNC_PORT", 6080))
NOVNC_DIR = os.environ.get("NOVNC_DIR", "")

CURSOR_COLORS = [
    "#ff6b6b", "#ffd93d", "#6bcb77", "#4d96ff",
    "#ff6b9d", "#c084fc", "#22d3ee", "#fb923c",
    "#a3e635", "#f472b6", "#38bdf8", "#e879f9",
]


# ═════════════════════════════════════════════════════════════════════════════
#  CURSOR SHARING
# ═════════════════════════════════════════════════════════════════════════════
class CursorRoom:
    def __init__(self):
        self.users = {}       # ws → dict
        self._cidx = 0

    def _color(self):
        c = CURSOR_COLORS[self._cidx % len(CURSOR_COLORS)]
        self._cidx += 1
        return c

    def user_list(self):
        return [
            {"username": u["username"], "color": u["color"]}
            for u in self.users.values()
        ]

    async def broadcast(self, msg, *, exclude=None):
        raw = json.dumps(msg)
        dead = []
        for ws in list(self.users):
            if ws is exclude:
                continue
            try:
                await ws.send_str(raw)
            except Exception:
                dead.append(ws)
        for ws in dead:
            await self.remove(ws)

    async def remove(self, ws):
        if ws not in self.users:
            return
        name = self.users[ws]["username"]
        del self.users[ws]
        print(f"  cursor: [-] {name}  ({len(self.users)} online)")
        await self.broadcast({"type": "users", "users": self.user_list()})
        await self.broadcast({"type": "left", "username": name})

    async def handle(self, request):
        ws = web.WebSocketResponse(heartbeat=20, max_msg_size=2**17)
        await ws.prepare(request)

        try:
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                    except (json.JSONDecodeError, TypeError):
                        continue

                    kind = data.get("type")

                    if kind == "join":
                        name = str(data.get("username", "Anon"))[:20].strip() or "Anon"
                        color = self._color()
                        self.users[ws] = {
                            "username": name,
                            "color": color,
                            "x": -1, "y": -1,
                            "visible": False,
                        }
                        await ws.send_str(json.dumps({
                            "type": "welcome",
                            "username": name,
                            "color": color,
                        }))
                        await self.broadcast(
                            {"type": "users", "users": self.user_list()}
                        )
                        # send existing cursors to the newcomer
                        for other, u in self.users.items():
                            if other is not ws and u["visible"]:
                                await ws.send_str(json.dumps({
                                    "type": "cursor",
                                    "username": u["username"],
                                    "color": u["color"],
                                    "x": u["x"], "y": u["y"],
                                    "visible": True,
                                }))
                        print(f"  cursor: [+] {name} {color}  "
                              f"({len(self.users)} online)")

                    elif kind == "move" and ws in self.users:
                        u = self.users[ws]
                        u["x"] = data.get("x", 0)
                        u["y"] = data.get("y", 0)
                        u["visible"] = data.get("visible", True)
                        await self.broadcast({
                            "type": "cursor",
                            "username": u["username"],
                            "color": u["color"],
                            "x": u["x"], "y": u["y"],
                            "visible": u["visible"],
                        }, exclude=ws)

                elif msg.type in (
                    WSMsgType.CLOSE, WSMsgType.CLOSING,
                    WSMsgType.CLOSED, WSMsgType.ERROR,
                ):
                    break
        except Exception:
            pass
        finally:
            await self.remove(ws)

        return ws


# ═════════════════════════════════════════════════════════════════════════════
#  VNC WEBSOCKET PROXY
# ═════════════════════════════════════════════════════════════════════════════
async def websockify_handler(request):
    ws = web.WebSocketResponse(protocols=["binary"], max_msg_size=0)
    await ws.prepare(request)
    print("  vnc: client connected")

    try:
        reader, writer = await asyncio.open_connection(VNC_HOST, VNC_PORT)
    except Exception as exc:
        print(f"  vnc: failed to connect to {VNC_HOST}:{VNC_PORT}: {exc}")
        await ws.close(code=1011, message=b"VNC unreachable")
        return ws

    stop = asyncio.Event()

    async def ws_to_vnc():
        try:
            async for msg in ws:
                if msg.type == WSMsgType.BINARY:
                    writer.write(msg.data)
                    await writer.drain()
                elif msg.type == WSMsgType.TEXT:
                    # noVNC may send text frames in some modes
                    writer.write(msg.data.encode() if isinstance(msg.data, str) else msg.data)
                    await writer.drain()
                elif msg.type in (WSMsgType.CLOSE, WSMsgType.CLOSING,
                                  WSMsgType.CLOSED, WSMsgType.ERROR):
                    break
        except Exception:
            pass
        finally:
            stop.set()

    async def vnc_to_ws():
        try:
            while not stop.is_set():
                data = await reader.read(65536)
                if not data:
                    break
                await ws.send_bytes(data)
        except Exception:
            pass
        finally:
            stop.set()

    t1 = asyncio.create_task(ws_to_vnc())
    t2 = asyncio.create_task(vnc_to_ws())

    try:
        await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
    except Exception:
        pass
    finally:
        t1.cancel()
        t2.cancel()
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        if not ws.closed:
            await ws.close()
        print("  vnc: client disconnected")

    return ws


# ═════════════════════════════════════════════════════════════════════════════
#  STATIC FILE SERVER
# ═════════════════════════════════════════════════════════════════════════════
async def static_handler(request):
    rel = request.match_info.get("path", "")
    if not rel or rel == "/":
        rel = "index.html"

    # Security: prevent directory traversal
    safe = os.path.normpath(os.path.join(NOVNC_DIR, rel))
    if not safe.startswith(os.path.normpath(NOVNC_DIR)):
        return web.Response(status=403, text="Forbidden")

    if os.path.isfile(safe):
        return web.FileResponse(safe)

    return web.Response(status=404, text="Not found")


# ═════════════════════════════════════════════════════════════════════════════
#  APP SETUP
# ═════════════════════════════════════════════════════════════════════════════
def create_app():
    room = CursorRoom()
    app = web.Application()

    # Order matters: explicit routes first, catch-all last
    app.router.add_get("/websockify", websockify_handler)
    app.router.add_get("/cursors", room.handle)
    app.router.add_get("/{path:.*}", static_handler)

    return app


def main():
    global NOVNC_DIR

    if not NOVNC_DIR:
        # Try to find noVNC relative to this script
        here = os.path.dirname(os.path.abspath(__file__))
        NOVNC_DIR = os.path.join(here, "vnc", "noVNC")

    if not os.path.isdir(NOVNC_DIR):
        print(f"FATAL: noVNC directory not found at {NOVNC_DIR}")
        sys.exit(1)

    print("╔════════════════════════════════════════╗")
    print(f"║  Combined Desktop Server               ║")
    print(f"║  Port {LISTEN_PORT}                            ║")
    print(f"║  /websockify → VNC :{VNC_PORT}              ║")
    print(f"║  /cursors    → cursor sharing          ║")
    print(f"║  /*          → {os.path.basename(NOVNC_DIR)} static     ║")
    print("╚════════════════════════════════════════╝")

    app = create_app()
    web.run_app(
        app,
        host="0.0.0.0",
        port=LISTEN_PORT,
        print=lambda s: print(f"  {s}"),
    )


if __name__ == "__main__":
    main()