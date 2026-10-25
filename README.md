# square-off-ios

iOS / iPadOS app for Square Off. SwiftUI, iOS 18+, dark-only.

Status: **design-refresh pass** on top of the server integration. The app follows the web client's design system (`square-off-react/square-off-app/docs/FRONTEND_DESIGN_SYSTEM.md`): the same tokens, Grapple + Chakra Petch Bold, the claim flip and corner spins (empty tiles stay dark on iOS), two-stroke shape draw-on, the GameScreen chrome, merged Play page, accordion rulebook, auth card, profile and stats. Every flow works against two backends, picked under Profile › Developer (debug builds) or with `-backend mock|live`:

- **Mock (default):** an in-app simulated server. Stateful REST mock (accounts, guests, games, turns, stats, replays; `demo` / `password`), an in-process room server with bot opponents for online play, and a simulated Level 3. Nothing to run.
- **Live:** the docker stack from `square-off-react` (branch `feature/ios-integration`). Real sign-in (password, Sign in with Apple, Google/GitHub), games recorded to Postgres, Level 3 (CNN) from the server, real rooms against the web client.

Local games (Vs Computer, Pass & Play) always play with the on-device rules and heuristics (levels 1, 2, 4, 5, 6 in `SquareOffCore/CPU`); the backend only records them and answers Level 3 (8×8, two players). An unfinished local game is saved on device and offered on Home and Play as "Continue game" (the header arrow keeps it; Leave / Home / New game discard it).

## Run it

`make phone` builds, installs and launches on the connected iPhone (`make devices` lists UDIDs; override with `DEVICE=` / `TEAM=`). `make build` / `make test` use the simulator.

1. Open `SquareOff.xcodeproj` in Xcode.
2. Pick the **SquareOff** scheme and any iPhone or iPad simulator, then Run (⌘R).

Debug shortcuts (Product › Scheme › Edit Scheme… › Run › Arguments):

| Argument | Effect |
|---|---|
| `-demoGame cpu\|cnn\|local4\|busy\|over` | jump into a game (Level 4, Level 3 on the live server, 4-player, a busy 12×12, a finished one) |
| `-demoScreen setup\|rules\|signin\|profile\|stats\|color\|forgot\|feedback` | open a screen or sheet (`-rulesSection <id>` with rules) |
| `-demoSignedIn YES` | restore the mock `demo` account at launch (pair with `-demoScreen profile\|stats`) |
| `-demoResetToken mock-reset-token-0123456789` | the reset-password sheet, as a universal link would open it |
| `-demoOnline host\|guest\|spectator\|quickmatch` | online flows against the mock room server with quick bots |
| `-backend production\|local\|mock` | backend for this launch (Release builds only know `production`) |

## Fonts, music, sounds

`SquareOff/Resources/Fonts/` bundles Grapple (`GrappleBRK`, the wordmark and short titles, copied from the web client) and Chakra Petch Bold (`ChakraPetch-Bold`, SIL Open Font License, `OFL-ChakraPetch.txt`; headings, buttons and every number). `Resources/Sounds/` holds `button.mp3`, `spin.mp3` and the looping `harmonies.mp3` ("Music by Missy Cundiff", off by default, toggled under Profile › Preferences or the in-game menu). `Theme.display(_:)` / `Theme.game(_:)` are the only places the font names appear.

## Backends

`production` is square-off.com and the only backend a Release build knows. Debug builds default to the in-app **mock** and can switch to **Local docker** or **Production** under Profile › Developer (or `-backend`). Shared invite links point at square-off.com except on local docker. When the server ends a session (`session_revoked`, `account_disabled`, an expired token) the app drops the token, falls back to the device guest and shows a toast; the mock's Developer panel has "Simulate revoked session".

## Local server

```bash
cd ../square-off-react/square-off-app && docker compose up -d --build db backend   # branch feature/ios-integration
cd - && scripts/trust-mkcert-simulator.sh          # once per simulator (booted), trusts the mkcert CA
```
Then Profile › Developer › **Local docker**, or launch with `-backend live`. Sign in with any account registered on the local server, or create one from the sign-in screen. Replays, stats and recent games need a signed-in account; guest games are still recorded.

The server side the app depends on is in `main` since the admin-console release (`Authorization: Bearer`, `POST /api/apple/native`, `?client=ios` on Google/GitHub login, WebSocket turn-ownership fixes) plus the `feature/ios-release` branch (`POST /api/account/delete`, `POST /api/password/forgot|reset`, the universal-links `apple-app-site-association` served by Caddy, `JWT_MOBILE_TOKEN_EXPIRE_MINUTES`). Run that branch in docker to exercise deletion, password reset and feedback end to end.

## Release

```bash
make bump BUILD=2            # or VERSION=1.0.1; edits project.yml and regenerates the project
make release-check           # Release archive + plist versions, entitlements, icon alpha, privacy manifest
make testflight ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>   # archive, export (ExportOptions.plist), upload
```
`make archive` / `make export` are the individual steps (`build-archive/`). The upload needs an App Store Connect API key (Users and Access › Integrations › App Store Connect API, role App Manager) saved as `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`.

What the store build carries, for App Review:
- Sign in with Apple next to Google and GitHub (guideline 4.8); guest play needs no account.
- Account deletion in two taps: Profile › Account › Delete account (5.1.1(v)); Apple-linked accounts re-authorise so the server can revoke the Apple session.
- `PrivacyInfo.xcprivacy`: no tracking, UserDefaults (CA92.1); data collected: email, name, user id (also a guest id), gameplay content, feedback — all linked to the user, none for tracking. The App Privacy answers in App Store Connect mirror that list.
- `ITSAppUsesNonExemptEncryption = false`, category Board games, universal links for `square-off.com/guest/*` and `/reset-password` (associated domains + the AASA served by the site).
- Review notes to include: a production demo account, "Level 3 uses our server; the other levels run on device", and that invite links open the app from a second device.
- Still to confirm before submitting: the licences for the Grapple font and the bundled music/SFX.

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
  Features/Play           Home (logo, Start Game / Online Match, Continue card, self-playing board), PlayView + PlaySetupModel
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
