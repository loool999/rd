#!/usr/bin/env python3
"""
Multi-user cursor sharing WebSocket server.
Each user sends their mouse position; the server broadcasts
all positions so every client can render remote cursors.
"""

import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
    import websockets

COLORS = [
    "#ff6b6b", "#ffd93d", "#6bcb77", "#4d96ff",
    "#ff6b9d", "#c084fc", "#22d3ee", "#fb923c",
    "#a3e635", "#f472b6", "#38bdf8", "#e879f9",
]


class CursorServer:
    def __init__(self):
        self.users = {}       # websocket → user_data dict
        self.color_index = 0

    # ── helpers ──────────────────────────────────────────────────────
    def next_color(self):
        c = COLORS[self.color_index % len(COLORS)]
        self.color_index += 1
        return c

    def user_list(self):
        return [
            {"username": u["username"], "color": u["color"]}
            for u in self.users.values()
        ]

    async def broadcast(self, msg, *, exclude=None):
        data = json.dumps(msg)
        gone = []
        for ws in list(self.users):
            if ws is exclude:
                continue
            try:
                await ws.send(data)
            except websockets.exceptions.ConnectionClosed:
                gone.append(ws)
        for ws in gone:
            await self.remove(ws)

    async def send(self, ws, msg):
        try:
            await ws.send(json.dumps(msg))
        except Exception:
            pass

    async def remove(self, ws):
        if ws not in self.users:
            return
        name = self.users[ws]["username"]
        del self.users[ws]
        print(f"[-] {name} left  ({len(self.users)} online)")
        await self.broadcast({"type": "users", "users": self.user_list()})
        await self.broadcast({"type": "left", "username": name})

    # ── per-connection handler ───────────────────────────────────────
    async def handler(self, ws, *args):
        """Handle one client.  *args catches the `path` param
        that older websockets versions pass."""
        try:
            async for raw in ws:
                try:
                    data = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue

                kind = data.get("type")

                # ── join ─────────────────────────────────────────
                if kind == "join":
                    name = str(data.get("username", "Anon"))[:20].strip() or "Anon"
                    color = self.next_color()
                    self.users[ws] = {
                        "username": name,
                        "color": color,
                        "x": -1, "y": -1,
                        "visible": False,
                    }
                    await self.send(ws, {
                        "type": "welcome",
                        "username": name,
                        "color": color,
                    })
                    # tell everyone the new user list
                    await self.broadcast({
                        "type": "users",
                        "users": self.user_list(),
                    })
                    # send existing cursors to the newcomer
                    for other_ws, u in self.users.items():
                        if other_ws is not ws and u["visible"]:
                            await self.send(ws, {
                                "type": "cursor",
                                "username": u["username"],
                                "x": u["x"],
                                "y": u["y"],
                                "color": u["color"],
                                "visible": True,
                            })
                    print(f"[+] {name} joined ({color})  "
                          f"({len(self.users)} online)")

                # ── cursor move ──────────────────────────────────
                elif kind == "move":
                    if ws in self.users:
                        u = self.users[ws]
                        u["x"] = data.get("x", 0)
                        u["y"] = data.get("y", 0)
                        u["visible"] = data.get("visible", True)
                        await self.broadcast({
                            "type": "cursor",
                            "username": u["username"],
                            "x": u["x"],
                            "y": u["y"],
                            "color": u["color"],
                            "visible": u["visible"],
                        }, exclude=ws)

        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            await self.remove(ws)


async def main():
    server = CursorServer()
    port = 6081

    print(f"Cursor server starting on 0.0.0.0:{port} ...")

    async with websockets.serve(
        server.handler,
        "0.0.0.0",
        port,
        ping_interval=20,
        ping_timeout=20,
        max_size=2**16,
    ):
        print(f"✓ Cursor server running  ws://0.0.0.0:{port}")
        await asyncio.Future()          # run forever


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCursor server stopped.")