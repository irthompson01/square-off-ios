# square-off-ios

iOS / iPadOS app for Square Off. SwiftUI, iOS 18+, dark-only.

Status: **design-refresh pass** on top of the server integration. The app follows the web client's design system (`square-off-react/square-off-app/docs/FRONTEND_DESIGN_SYSTEM.md`): the same tokens, Grapple + Chakra Petch Bold, the claim flip and corner spins (empty tiles stay dark on iOS), two-stroke shape draw-on, the GameScreen chrome, merged Play page, accordion rulebook, auth card, profile and stats. Every flow works against two backends, picked under Profile › Developer (debug builds) or with `-backend mock|live`:

- **Mock (default):** an in-app simulated server. Stateful REST mock (accounts, guests, games, turns, stats, replays; `demo` / `password`), an in-process room server with bot opponents for online play, and a simulated Level 3. Nothing to run.
- **Live:** the docker stack from `square-off-react` (branch `feature/ios-integration`). Real sign-in (password, Sign in with Apple, Google/GitHub), games recorded to Postgres, Level 3 (CNN) from the server, real rooms against the web client.

Local games (Vs Computer, Pass & Play) always play with the on-device rules and heuristics (levels 1, 2, 4, 5, 6 in `SquareOffCore/CPU`); the backend only records them and answers Level 3 (8×8, two players). An unfinished local game is saved on device and offered on Home and Play as "Continue game" (the header arrow keeps it; Leave / Home / New game discard it).

## Run it

1. Open `SquareOff.xcodeproj` in Xcode.
2. Pick the **SquareOff** scheme and any iPhone or iPad simulator, then Run (⌘R).

Debug shortcuts (Product › Scheme › Edit Scheme… › Run › Arguments):

| Argument | Effect |
|---|---|
| `-demoGame cpu\|cnn\|local4\|busy\|over` | jump into a game (Level 4, Level 3 on the live server, 4-player, a busy 12×12, a finished one) |
| `-demoScreen home\|setup\|rules\|signin\|profile\|stats\|color` | open a screen (`-rulesSection <id>` with rules) |
| `-demoSignedIn YES` | restore the mock `demo` account at launch (pair with `-demoScreen profile\|stats`) |
| `-demoOnline host\|guest\|spectator\|quickmatch` | online flows against the mock room server with quick bots |
| `-backend mock\|live` | backend for this launch |

## Fonts, music, sounds

`SquareOff/Resources/Fonts/` bundles Grapple (`GrappleBRK`, the wordmark and short titles, copied from the web client) and Chakra Petch Bold (`ChakraPetch-Bold`, SIL Open Font License, `OFL-ChakraPetch.txt`; headings, buttons and every number). `Resources/Sounds/` holds `button.mp3`, `spin.mp3` and the looping `harmonies.mp3` ("Music by Missy Cundiff", off by default, toggled under Profile › Preferences or the in-game menu). `Theme.display(_:)` / `Theme.game(_:)` are the only places the font names appear.

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
  App/                    Entry point, AppModel, theme tokens + primitives, toasts, starfield
  Services/Backend        BackendConfiguration + Backend (mock | live), token stores, identities,
                          AccountStore, ServerGameRecorder, ServerCPUMoveProvider
  Features/Play           Home (wordmark + neon tiles + Continue card), PlayView + PlaySetupModel, colour picker
  Features/Game           GamePresenting, GameSession (local), board (flip / spins / shape draw-on), chrome, sheets
  Features/Online         RoomCoordinator (lobby), OnlineGameSession, OnlineConnection, OnlinePanel, WaitingRoomView
  Features/Learn          Accordion rulebook with the web's 13 scripted demo boards
  Features/Profile        Auth card, profile rows + inline edit, StatsView (donut, filters, history), ReplayView
  Services/               SoundPlayer (SFX), MusicPlayer (loop), LocalGameStore (Continue game)
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
