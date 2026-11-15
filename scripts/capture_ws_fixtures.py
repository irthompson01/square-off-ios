#!/usr/bin/env python3
"""
Records every message the game socket sends during a scripted host/guest/spectator session,
as JSON fixtures for SquareOffNetTests (WSDecodingTests).

Since the 2026-11 server every socket needs a session: the script mints one guest per role
with `POST /api/create_guest` and sends its token as `Authorization: Bearer` on the handshake
(what `LiveGameSocket` does). It also provokes the session refusals the app handles:
`JOIN_ERROR already_seated` / `seat_taken` and `REJOIN_FAILED not_your_seat`.

Run it where the `websockets` and `httpx` packages exist, e.g. inside the backend image on the
compose network:
    docker run --rm --network square-off-app_custom_bridge \
      -v "$PWD/scripts:/scripts" -v "$PWD/Packages/SquareOffKit/Tests/SquareOffNetTests/Fixtures/ws:/out" \
      squareoff/backend:latest python /scripts/capture_ws_fixtures.py --url wss://backend:8002/ws --out /out
"""

import argparse
import asyncio
import json
import os
import ssl

import httpx
import websockets

SIZE = 6


def seat(slot, name, color, player_id=None):
    return {"id": slot, "name": name, "fillStyle": color, "isCPU": False, "currentScore": 0, "currentMultiplier": 1,
            "playerId": player_id}


def move(row, col):
    return {"type": "GAME_UPDATE", "gameState": {"rowIndex": row, "colIndex": col}}


class Recorder:
    def __init__(self, out):
        self.out = out
        self.counts = {}
        self.seen = set()

    def record(self, role, message):
        kind = message.get("type", "UNKNOWN")
        key = json.dumps(message, sort_keys=True)
        if key in self.seen:
            return
        self.seen.add(key)
        n = self.counts.get(kind, 0) + 1
        self.counts[kind] = n
        with open(os.path.join(self.out, f"{kind}_{n}.json"), "w") as f:
            json.dump(message, f, indent=2)
            f.write("\n")
        print(f"[{role}] {kind} -> {kind}_{n}.json")


async def drain(ws, role, recorder, seconds=0.6):
    try:
        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=seconds)
            recorder.record(role, json.loads(raw))
    except (asyncio.TimeoutError, websockets.ConnectionClosed):
        pass


def api_base(ws_url):
    return ws_url.replace("wss://", "https://").replace("ws://", "http://").rsplit("/ws", 1)[0] + "/api"


async def mint_guest(base_url, name):
    # One client per guest: the server sets its session cookie and would renew the same guest
    # for every later call on a client that keeps cookies.
    async with httpx.AsyncClient(base_url=base_url, verify=False, timeout=15) as client:
        r = await client.post("/create_guest", json={"name": name, "color": "#0583D2"})
        r.raise_for_status()
        body = r.json()
        return body["player_id"], body["access_token"]


def connect(url, ctx, token):
    return websockets.connect(url, ssl=ctx, additional_headers={"Authorization": f"Bearer {token}"})


async def main(url, out):
    os.makedirs(out, exist_ok=True)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    rec = Recorder(out)
    base = api_base(url)
    host_id, host_token = await mint_guest(base, "Host")
    guest_id, guest_token = await mint_guest(base, "Guest")
    _, spectator_token = await mint_guest(base, "Spectator")
    _, late_token = await mint_guest(base, "Late")

    async with connect(url, ctx, host_token) as host, connect(url, ctx, guest_token) as guest, \
            connect(url, ctx, spectator_token) as spectator:
        async def step(sender, message, *waiters):
            await sender.send(json.dumps(message))
            await asyncio.gather(*(drain(ws, role, rec) for ws, role in waiters))

        await step(host, {"type": "CREATE_ROOM", "player": seat(1, "Host", "#0583D2", host_id),
                          "gameState": {"boardSize": SIZE, "boardState": [[None] * SIZE for _ in range(SIZE)]},
                          "timer": 20}, (host, "host"))
        created = next(json.load(open(os.path.join(out, f))) for f in os.listdir(out) if f.startswith("ROOM_CREATED"))
        code = created["roomCode"]
        await step(guest, {"type": "REQUEST_PLAYER_SLOT", "roomCode": code}, (guest, "guest"))
        await step(guest, {"type": "JOIN_ROOM", "roomCode": code, "player": seat(2, "Guest", "#FF3131", guest_id)},
                   (host, "host"), (guest, "guest"))

        # Session refusals: the guest's token on a second socket wants another seat; a stranger
        # wants the guest's seat; a stranger tries to rejoin it.
        async with connect(url, ctx, guest_token) as second_tab:
            await step(second_tab, {"type": "JOIN_ROOM", "roomCode": code, "player": seat(3, "Guest again", "#50C878", guest_id)},
                       (second_tab, "guest-second-tab"))
        async with connect(url, ctx, late_token) as late:
            await step(late, {"type": "JOIN_ROOM", "roomCode": code, "player": seat(2, "Late", "#F5A623", None)}, (late, "late"))
            await step(late, {"type": "REJOIN_ROOM", "roomCode": code, "playerId": 2, "role": "guest"}, (late, "late"))

        await step(host, {"type": "GAME_START"}, (host, "host"), (guest, "guest"))
        for sender, (r, c) in [(host, (0, 0)), (guest, (5, 5)), (host, (0, 1)), (guest, (5, 4)), (host, (1, 0)), (guest, (4, 5)), (host, (1, 1))]:
            await step(sender, move(r, c), (host, "host"), (guest, "guest"))
        await step(host, {"type": "TURN_COMPLETE"}, (host, "host"), (guest, "guest"))   # the host's clock skips the guest
        await step(guest, {"type": "TURN_COMPLETE"}, (host, "host"), (guest, "guest"))  # ignored: not the host
        await step(guest, move(2, 2), (guest, "guest"))              # out of turn → MOVE_REJECTED
        await step(host, move(0, 0), (host, "host"))                 # occupied → MOVE_REJECTED
        await step(spectator, {"type": "JOIN_AS_SPECTATOR", "roomCode": code}, (host, "host"), (guest, "guest"), (spectator, "spectator"))
        await step(host, {"type": "GAME_RESET", "boardSize": SIZE, "timer": 20}, (host, "host"), (guest, "guest"), (spectator, "spectator"))
        await guest.close()
        await drain(host, "host", rec, 1.0)
        await drain(spectator, "spectator", rec, 0.3)
        await step(spectator, {"type": "REJOIN_ROOM", "roomCode": code, "playerId": 0, "role": "spectator"}, (spectator, "spectator"))
        await host.close()
        await drain(spectator, "spectator", rec, 1.0)
    print("done:", dict(sorted(rec.counts.items())))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="wss://localhost:8002/ws")
    parser.add_argument("--out", default="Packages/SquareOffKit/Tests/SquareOffNetTests/Fixtures/ws")
    args = parser.parse_args()
    asyncio.run(main(args.url, args.out))
