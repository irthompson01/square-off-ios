# square-off-ios

iOS / iPadOS app for Square Off. SwiftUI, iOS 18+, dark-only.

Status: **v1 mock layout**. Local games (Vs Computer, Pass & Play) are fully playable with the real rules. Server calls go through a mock by default. Online screens are mocked.

## Run it

1. Open `SquareOff.xcodeproj` in Xcode.
2. Pick the **SquareOff** scheme and any iPhone or iPad simulator, then Run (⌘R).

Debug shortcut: add the launch argument `-demoGame cpu` (or `-demoGame local4`) under *Scheme › Run › Arguments* to jump straight into a game.

## Tests

- **In Xcode:** ⌘U runs everything: app tests, plus the rules and networking package tests.
- **Package tests only (fast, no simulator):**
  ```bash
  cd Packages/SquareOffKit && swift test
  ```
- **Live contract tests** against the local server (same requests as the web client):
  ```bash
  cd ../square-off-react/square-off-app && docker compose up -d --no-build db backend
  cd - && cd Packages/SquareOffKit && SQUAREOFF_LIVE_API=1 swift test --filter Live
  ```

## Using the local server from the app

The app runs on a mock backend by default. To use the docker-compose server:

1. Start it: `docker compose up -d --no-build db backend` in `square-off-react/square-off-app`. It serves `https://localhost:8002/api`.
2. Make the simulator trust the mkcert certificate (once per simulator):
   ```bash
   xcrun simctl keychain booted add-root-cert "$(mkcert -CAROOT)/rootCA.pem"
   ```
3. In the app: **Profile › Developer › Backend → Local server**.

Games started this way follow the web's request order (`/guests` → `/cpu_player/{type}` → `/start` → `/{id}/turns` per move, `/cpu_move` on CPU turns) and are written to your local database.

## Layout

```
SquareOff/                App target (SwiftUI)
  App/                    Entry point, AppModel, theme tokens
  Features/Play           Home, mode picker, setup (iPad: side by side)
  Features/Game           GameSession, board + tile spins + shape panes, sheets
  Features/Online         Mock quick match / rooms / waiting room
  Features/Learn          How to play
  Features/Profile        Guest/password sign-in, settings, backend switch
  Services/SoundPlayer    SFX with slight pitch variation
Packages/SquareOffKit/
  SquareOffCore           Rules engine (port of hero-client/src/modules)
  SquareOffNet            REST DTOs + Live/Mock clients (mirrors hero-client/src/services)
SquareOffTests/           App-level tests (GameSession request order)
project.yml               XcodeGen spec. Run `xcodegen generate` after adding/removing files
docs/UI_RESEARCH.md       Research, decisions, server contract notes
```

Wireframes: https://claude.ai/artifact/NG8NSVMUej4QsuT3wZSVY4
