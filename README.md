# square-off-ios

iOS / iPadOS app for Square Off. SwiftUI, iOS 18+, dark-only.

Status: **v1 guest-only pass**. Local games (Vs Computer, Pass & Play) are fully playable offline with the real rules. CPU levels 1, 2, 4, 5 and 6 are computed on device (`SquareOffCore/CPU`, a port of the server's heuristics); level 3 (CNN) needs the server and is greyed out. No sign-in and no server calls in the game flow. Online and sign-in screens are mockups.

## Run it

1. Open `SquareOff.xcodeproj` in Xcode.
2. Pick the **SquareOff** scheme and any iPhone or iPad simulator, then Run (⌘R).

Debug shortcuts (Product › Scheme › Edit Scheme… › Run › Arguments): `-demoGame cpu|local4|busy|over` jumps into a game (a busy 12×12, or a finished one); `-demoScreen rules|setup|color|signin` opens a screen, with `-rulesSection <id>` (e.g. `section-gameplay`) to land on a rulebook section.

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

## Command line

`xcode-select` on this machine may point at the Command Line Tools, which lack `xcodebuild`, `simctl` and the Swift Testing module. Either run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate                                    # after editing project.yml or adding files
xcodebuild -project SquareOff.xcodeproj -scheme SquareOff \
  -destination 'platform=iOS Simulator,name=iPhone 17' build test
```

## Server

The app target links only `SquareOffCore`. `SquareOffNet` (DTOs + Live/Mock clients mirroring `hero-client/src/services`) stays in the package with its contract tests, ready for a later pass that records games or fetches CPU moves from the server. `GameSession` already takes a `CPUMoveProvider` and a `GameRecorder`, so that pass won't touch the screens.

## Layout

```
SquareOff/                App target (SwiftUI)
  App/                    Entry point, AppModel, theme tokens
  Features/Play           Home, mode picker, setup (iPad: side by side)
  Features/Game           GameSession (local rules + on-device CPU), board + tile spins + shape panes, sheets
  Features/Online         Mock quick match / rooms / waiting room
  Features/Learn          Full rulebook (port of hero-client's rulebook-content.ts) with live mini-board demos
  Features/Profile        Guest card, settings, static sign-in mockup
  Services/SoundPlayer    SFX with slight pitch variation
Packages/SquareOffKit/
  SquareOffCore           Rules engine (port of hero-client/src/modules) + CPU/ (port of server/src/routes/model.py)
  SquareOffNet            REST DTOs + Live/Mock clients (mirrors hero-client/src/services); not linked by the app yet
SquareOffTests/           App-level tests (GameSession turn flow with scripted CPU / recorder)
project.yml               XcodeGen spec. Run `xcodegen generate` after adding/removing files
docs/UI_RESEARCH.md       Research, decisions, server contract notes
```

Wireframes: https://claude.ai/artifact/NG8NSVMUej4QsuT3wZSVY4
