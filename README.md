# square-off-ios

iOS / iPadOS app for Square Off. SwiftUI, iOS 18+, dark-only.

Status: **server-integration pass**. Every flow works against two backends, picked under Profile › Developer (debug builds) or with `-backend mock|live`:

- **Mock (default):** an in-app simulated server. Stateful REST mock (accounts, guests, games, turns, stats, replays; `demo` / `password`), an in-process room server with bot opponents for online play, and a simulated Level 3. Nothing to run.
- **Live:** the docker stack from `square-off-react` (branch `feature/ios-integration`). Real sign-in (password, Sign in with Apple, Google/GitHub), games recorded to Postgres, Level 3 (CNN) from the server, real rooms against the web client.

Local games (Vs Computer, Pass & Play) always play with the on-device rules and heuristics (levels 1, 2, 4, 5, 6 in `SquareOffCore/CPU`); the backend only records them and answers Level 3 (8×8, two players).

## Run it

1. Open `SquareOff.xcodeproj` in Xcode.
2. Pick the **SquareOff** scheme and any iPhone or iPad simulator, then Run (⌘R).

Debug shortcuts (Product › Scheme › Edit Scheme… › Run › Arguments):

| Argument | Effect |
|---|---|
| `-demoGame cpu\|cnn\|local4\|busy\|over` | jump into a game (Level 4, Level 3 on the live server, 4-player, a busy 12×12, a finished one) |
| `-demoScreen rules\|setup\|color\|signin` | open a screen (`-rulesSection <id>` with rules) |
| `-demoOnline host\|guest\|spectator\|quickmatch` | online flows against the mock room server with quick bots |
| `-backend mock\|live` | backend for this launch |

## Local server

```bash
cd ../square-off-react/square-off-app && docker compose up -d --build db backend   # branch feature/ios-integration
cd - && scripts/trust-mkcert-simulator.sh          # once per simulator (booted), trusts the mkcert CA
```
Then Profile › Developer › **Local docker**, or launch with `-backend live`. Sign in with any account registered on the local server, or create one from the sign-in screen. Replays, stats and recent games need a signed-in account; guest games are still recorded.

The server branch adds what the app needs (`Authorization: Bearer` alongside the cookie, `POST /api/apple/native`, `?client=ios` on Google/GitHub login, and three WebSocket fixes: turn ownership, no turn advance on a bad move, seats kept during a match). The web client is unchanged.

## Tests

- **In Xcode:** ⌘U runs everything: app tests, plus the rules and networking package tests.
- **Package tests only (fast, no simulator):**
  ```bash
  cd Packages/SquareOffKit && swift test
  ```
- **Live contract tests** against the docker server (REST with a bearer token, CNN, two real sockets):
  ```bash
  cd Packages/SquareOffKit && SQUAREOFF_LIVE_API=1 swift test --filter Live
  ```
- **Server tests** (inside the backend image, no DB): `make test-server` in `square-off-react/square-off-app`.
- Fixtures: REST responses in `Tests/SquareOffNetTests/Fixtures/`, socket messages in `Fixtures/ws/` captured with `scripts/capture_ws_fixtures.py` (see its header for the docker command).

## Command line

`xcode-select` on this machine may point at the Command Line Tools, which lack `xcodebuild`, `simctl` and the Swift Testing module. Either run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate                                    # after editing project.yml or adding files
xcodebuild -project SquareOff.xcodeproj -scheme SquareOff \
  -destination 'platform=iOS Simulator,name=iPhone 17' build test
```

## Layout

```
SquareOff/                App target (SwiftUI)
  App/                    Entry point, AppModel, theme tokens, starfield
  Services/Backend        BackendConfiguration + Backend (mock | live), token stores, identities,
                          AccountStore, ServerGameRecorder, ServerCPUMoveProvider
  Features/Play           Home, mode picker, setup (iPad: side by side)
  Features/Game           GamePresenting, GameSession (local), board + tile spins + shape panes, sheets
  Features/Online         RoomCoordinator (lobby), OnlineGameSession, OnlineConnection, hub / waiting room / open rooms
  Features/Learn          Full rulebook with live mini-board demos
  Features/Profile        Account card, sign-in (password / Apple / Google / GitHub), stats, recent games, ReplayView
  Services/SoundPlayer    SFX with slight pitch variation
Packages/SquareOffKit/
  SquareOffCore           Rules engine + CPU/ (port of server/src/routes/model.py)
  SquareOffNet            REST contract (Live + stateful Mock), MatcherAPI, WS/ (wire types, Game bridge,
                          GameSocket, LiveGameSocket, MockRoomServer with bots, MockMatcherAPI)
SquareOffTests/           App-level tests (session flow, recorder, account store, online rooms)
scripts/                  trust-mkcert-simulator.sh, capture_ws_fixtures.py
project.yml               XcodeGen spec. Run `xcodegen generate` after adding/removing files
docs/UI_RESEARCH.md       Research, decisions, server contract notes
```

Wireframes: https://claude.ai/artifact/NG8NSVMUej4QsuT3wZSVY4
