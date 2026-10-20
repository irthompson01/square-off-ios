#!/usr/bin/env python3
"""
Records every message the game socket sends during a scripted host/guest/spectator session,
as JSON fixtures for SquareOffNetTests (WSDecodingTests).

Run it where the `websockets` package exists, e.g. inside the backend image on the compose network:
    docker run --rm --network square-off-app_custom_bridge \
      -v "$PWD/scripts:/scripts" -v "$PWD/Packages/SquareOffKit/Tests/SquareOffNetTests/Fixtures/ws:/out" \
      squareoff/backend:latest python /scripts/capture_ws_fixtures.py --url wss://backend:8002/ws --out /out
"""

import argparse
import asyncio
import json
import os
import ssl

import websockets

SIZE = 6


def seat(slot, name, color):
    return {"id": slot, "name": name, "fillStyle": color, "isCPU": False, "currentScore": 0, "currentMultiplier": 1}


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


async def main(url, out):
    os.makedirs(out, exist_ok=True)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    rec = Recorder(out)
    async with websockets.connect(url, ssl=ctx) as host, websockets.connect(url, ssl=ctx) as guest, websockets.connect(url, ssl=ctx) as spectator:
        async def step(sender, message, *waiters):
            await sender.send(json.dumps(message))
            await asyncio.gather(*(drain(ws, role, rec) for ws, role in waiters))

        await step(host, {"type": "CREATE_ROOM", "player": seat(1, "Host", "#0583D2"),
                          "gameState": {"boardSize": SIZE, "boardState": [[None] * SIZE for _ in range(SIZE)]},
                          "timer": 20}, (host, "host"))
        created = next(json.load(open(os.path.join(out, f))) for f in os.listdir(out) if f.startswith("ROOM_CREATED"))
        code = created["roomCode"]
        await step(guest, {"type": "REQUEST_PLAYER_SLOT", "roomCode": code}, (guest, "guest"))
        await step(guest, {"type": "JOIN_ROOM", "roomCode": code, "player": seat(2, "Guest", "#FF3131")},
                   (host, "host"), (guest, "guest"))
        await step(host, {"type": "GAME_START"}, (host, "host"), (guest, "guest"))
        for sender, (r, c) in [(host, (0, 0)), (guest, (5, 5)), (host, (0, 1)), (guest, (5, 4)), (host, (1, 0)), (guest, (4, 5)), (host, (1, 1))]:
            await step(sender, move(r, c), (host, "host"), (guest, "guest"))
        await step(guest, {"type": "TURN_COMPLETE"}, (host, "host"), (guest, "guest"))
        await step(guest, move(2, 2), (guest, "guest"))              # out of turn → MOVE_REJECTED
        await step(host, move(0, 0), (host, "host"))                 # occupied → MOVE_REJECTED
        await step(spectator, {"type": "JOIN_AS_SPECTATOR", "roomCode": code}, (host, "host"), (guest, "guest"), (spectator, "spectator"))
        await step(host, {"type": "GAME_RESET", "boardSize": SIZE, "timer": 20}, (host, "host"), (guest, "guest"), (spectator, "spectator"))
        await guest.close()
        await drain(host, "host", rec, 1.0)
        await drain(spectator, "spectator", rec, 0.3)
        await step(guest if False else spectator, {"type": "REJOIN_ROOM", "roomCode": code, "playerId": 0, "role": "spectator"}, (spectator, "spectator"))
        await host.close()
        await drain(spectator, "spectator", rec, 1.0)
    print("done:", dict(sorted(rec.counts.items())))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="wss://localhost:8002/ws")
    parser.add_argument("--out", default="Packages/SquareOffKit/Tests/SquareOffNetTests/Fixtures/ws")
    args = parser.parse_args()
    asyncio.run(main(args.url, args.out))
