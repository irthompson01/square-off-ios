# iOS UI Research: Square Off

Status: research / design only, with no app code yet. Wireframes: https://claude.ai/artifact/NG8NSVMUej4QsuT3wZSVY4

**v1 scope:** iPhone + iPad (universal app). Vs Computer (all 6 levels, same as web), Pass & Play, and Online over the existing WebSocket server. **Parity rule:** v1 uses the server's REST and WebSocket contracts exactly as the web client does (see "REST contract parity").

## What we're porting

Source: `square-off-react/square-off-app/hero-client`

| Web (React) | Role | iOS equivalent |
| --- | --- | --- |
| HeroUI v3 + Tailwind | Component library + styling | **SwiftUI** (no Swift port of HeroUI exists. HeroUI Native targets React Native) |
| react-konva (`game-board.tsx`, `game-tile.tsx`) | Board canvas, tile flip/rotate animations | SwiftUI `Grid` + `rotationEffect` / `rotation3DEffect`, `Path` overlay for shape lines |
| `ANIMATED_LINE_DRAW.md` line draw | Shape outline animation | `Path` + `.trim(from:to:)` animated |
| recharts (`stats-line-chart.tsx`, profile donuts) | Charts | **Swift Charts** (`LineMark`, `SectorMark`) |
| motion, @number-flow/react | Transitions, animated score numbers | SwiftUI animations, `.contentTransition(.numericText())` |
| lucide / gravity icons | Icons | SF Symbols |
| `StarsAnimation` | Starfield background | `TimelineView` + `Canvas` |
| `audioService.ts` (button.mp3, spin.mp3) | SFX + music | `AVAudioEngine` for SFX, `AVAudioPlayer` for music |
| — | Haptics | Core Haptics (`CHHapticEngine`), `.sensoryFeedback` for simple cases |
| `use-game-socket.ts` | WebSocket game | `URLSessionWebSocketTask` |
| `server/src/routes/model.py` `/cpu_move` | CPU opponents | Same `POST /cpu_move` call as web (v1). On-device port is a later option |
| Google OAuth | Auth | Sign in with Apple (`AuthenticationServices`) + Google SDK |

## Options compared

### 1. SwiftUI only (recommended)
- A turn-based grid game with at most 12×12 = 144 tiles is well within what SwiftUI renders smoothly. No game loop needed.
- Menus, forms, sheets, navigation, Dynamic Type, VoiceOver and dark mode come free. The current iOS look (Liquid Glass tab bars and sheets) comes automatically with standard components.
- iPad layouts come from the same views via size classes.
- Swift Charts covers the stats pages with no third-party chart library.

### 2. SwiftUI shell + SpriteKit board (`SpriteView`)
- Gives particle effects, physics and a frame loop. Square Off needs none of those. The tile spins are plain transform animations that SwiftUI does at 120Hz.
- Adds a second coordinate system and harder accessibility (SpriteKit nodes aren't VoiceOver elements by default).
- Revisit only if we later want heavy particle/celebration effects.

### 3. UIKit
- No advantage for a new app here. Use `UIViewRepresentable` only for a one-off gap.

### 4. Cross-platform (React Native / Expo, Flutter)
- Out of scope since we want Swift. Expo could have reused the TS game logic and HeroUI Native. That is the trade-off we are giving up.

## CPU opponents

**v1 decision:** keep all 6 levels with the web's numbering. The app calls `POST /cpu_move` with the same payload as `modelAPI.cpuMove` (`game_id`, `board_state`, `current_player`, `game_players`, `cpu_type`).

| Level | `cpu_type` |
| --- | --- |
| 1 | `random` |
| 2 | `max-random` |
| 3 | `cnn` |
| 4 | `max-min` |
| 5 | `max-min-optimal` |
| 6 | `max-min-io` |

**Blocker for Level 3, on web and iOS alike:** the server's `CNN_MODEL = load_model(...)` is commented out in `model.py`, so `cpu_type: "cnn"` currently returns a 500 error. It's also hardcoded to 8×8 boards and 2 players (`np.zeros((8, 8, 2))`). Before launch, the server needs one of two fixes:
- re-enable the model, and either restrict Level 3 to 8×8 two-player games in setup or return a clean 4xx error;
- or make setup hide Level 3 for other board sizes. That needs the same rule on web.

**Later option: on-device heuristics.** Levels 1, 2, 4, 5 and 6 are a clean port if we ever want offline play (details below). Level 3 could follow via Core ML (`coremltools` from the `.keras` file).

### How the heuristic levels work (reference for an on-device port)

**How they work** (`server/src/routes/model.py`). Every heuristic level is a *one-move lookahead*, not a deep search. For each empty tile: copy the board, place the tile for the CPU (and, for Max-Min variants, for the next player), scan for new squares/diamonds, score it, then pick by a rule:

| Level | `cpu_type` | Rule |
| --- | --- | --- |
| 1 Random | `random` | Random empty tile |
| 2 Max-Random | `max-random` | Highest own score gain. Ties → prefer higher multiplier, then non-adjacent, then random |
| 4 Max-Min | `max-min` | Best scoring move. Else best blocking move (opponent's highest gain). Else random non-adjacent |
| 5 Max-Min-Optimal | `max-min-optimal` | Maximize `max(own gain, opponent gain)`, so it scores or blocks, whichever is bigger. Else random non-adjacent |
| 6 Max-Min-IO | `max-min-io` | Same as 5, but with no scoring/blocking move it takes the non-adjacent tile closest to the center |

**Cost:** worst case is 12×12 at move 1. That's 144 candidates × 2 simulated boards × about 1,000 square/diamond position checks, roughly 300k cheap integer comparisons. In Swift with value-type boards that takes milliseconds. Python on the server is slower mostly because of `deepcopy` per candidate. Incremental detection (only check shapes that include the new tile) would make it O(n²) per candidate, but we don't need it.

**Benefits of a later on-device port:** works offline, no server load, no `MODEL_CPU_MOVE` rate limit, no network round trip.

**Porting notes (later):**
- Logic goes in `SquareOffCore`: `Board`, square/diamond detection, `calculate_score` (multiplier rules), the strategies.
- Golden tests: feed the same board JSON to Python and Swift and compare scores and candidate move *sets*. Exact moves differ because of random tie-breaks.
- The Max-Min variants only simulate the *next* player as "the opponent". In 3–4 player games they ignore everyone else.

**Even in v1, local games need rules on device.** With `/cpu_move` the server picks the CPU's move, but local and CPU games still need the client to detect shapes, score and animate. The web does that in `modules/board-logic.ts` and `game-move-engine.ts`, so those get ported to Swift either way.

## REST contract parity

Goal: the iOS app calls the same endpoints, with the same payloads, in the same order as the web client. Base URL = the web's `VITE_API_URL`. Source: `hero-client/src/services/*.ts`.

**Which calls each flow makes (from the web pages):**

| Flow | Calls, in order |
| --- | --- |
| App launch | `GET /check-auth` (cookie) |
| Login / register | `POST /register` → `POST /login` (sets cookie); `GET /google/login`, `GET /github/login` |
| Setup (CPU / local) | `GET /profile`, `GET /guests`, `GET /cpu_player/{cpu_type}` → `POST /start` (returns `gameId`) |
| Each turn (local / CPU) | `POST /{gameId}/turns`, plus `POST /cpu_move` on CPU turns |
| Online host | `POST /start`, `PUT /update/players`, `POST /matcher/advertise`, `DELETE /matcher/advertise/{roomCode}` + WebSocket `/ws` |
| Lobby / quick match | `GET /matcher/open`, `POST /matcher/quick-match`, `GET …/quick-match` status poll, `POST /matcher/quick-match/cancel`, `GET /guests` |
| Profile | `GET /profile`, `PATCH /profile` |
| Stats | `GET /stats_view`, `/stats_view_cpu`, `/stats_view_human`, filters, recent games, `GET /{gameId}/replay` |
| Feedback | `POST /feedback` |
| Logout | `POST /logout` |

`PUT /end` and `GET /stats/{playerId}` exist in `gameAPI.ts`, but no web page calls them. Admin endpoints are web-only.

**Auth works the same way natively, except OAuth:**
- **Password login:** `POST /login` sets an httpOnly cookie, `square_off_access_token`. `URLSession` stores and sends cookies automatically through `HTTPCookieStorage`, the equivalent of the web's `credentials: "include"`. One check: cookies set with `samesite=none; secure` and an explicit `domain` must match the API host. A native client ignores SameSite, so that part is fine.
- **Cookie persistence:** the login cookie sets `max_age = JWT_ACCESS_TOKEN_EXPIRE_MINUTES × 60`, so it survives app restarts until the JWT expires. There's no refresh endpoint, so users get signed out when it expires, same as web. On a phone that feels worse, because people expect to stay signed in.
- **Google / GitHub OAuth can't be copied as-is.** The callback sets the cookie and then redirects to the *web frontend URL*. On iOS, OAuth runs in `ASWebAuthenticationSession`, whose browser cookie jar is separate from the app's `URLSession`. The server needs a small mobile variant: callback → redirect to `squareoff://auth?code=<one-time code>` (or a universal link), then the app trades the code for the cookie.
- **Sign in with Apple** is a new endpoint either way: the app posts Apple's identity token, and the server verifies it and sets the same cookie.
- **The web stores some state in `sessionStorage`:** online session/rejoin info, the local game snapshot, and the lobby `requester_id`. On iOS these become app storage, mirroring the same keys and shapes.

**Keep it in sync:** generate Swift `Codable` models from the FastAPI OpenAPI schema (`/openapi.json`, e.g. with Apple's `swift-openapi-generator`) or hand-write them from `schemas.py`. Then add contract tests that hit a local server (docker-compose) with the same requests the web makes.

## Online multiplayer: WebSocket

The protocol is a good fit for a thin native client.

**What's there** (`server/src/routes/websocket.py`, `schemas.py`):
- **One endpoint, plain JSON:** a single `/ws` endpoint with JSON messages tagged by `type`.
  - Client → server: `CREATE_ROOM`, `JOIN_ROOM`, `JOIN_AS_SPECTATOR`, `REJOIN_ROOM`, `GAME_START`, `GAME_UPDATE` (a move: `rowIndex`/`colIndex`), `TURN_COMPLETE` (timer expired), `REQUEST_PLAYER_SLOT`, `GAME_RESET`.
  - Server → client: `ROOM_CREATED`, `PLAYER_JOINED`, `GAME_STATE`, `GAME_UPDATE`, `GAME_START`, `GAME_RESET`, `HOST_AWAY` / `GUEST_AWAY`, `HOST_DISCONNECTED`, `PLAYER_REJOINED`, `REJOIN_FAILED`, `SPECTATOR_*`, `PROMOTED_TO_PLAYER`, `JOIN_ERROR` / `GAME_ERROR`.
- **Server-authoritative:** the client sends only row/col, the server runs `game.make_move`, and it broadcasts the full state plus `scoreIncrease`, `multiplierIncrease` and `newShapes`. iOS can render that and trigger the spin/outline animations from `newShapes`, with no rules engine needed for online play.
- **Reconnect windows:** after a drop, a host has 60s and a guest 30s to send `REJOIN_ROOM`.
- **Matchmaking:** Quick Match and the lobby go through REST (`routes/matcher.py`), then hand off to the socket.

**iOS client design:**
- **Transport:** `URLSessionWebSocketTask`, wrapped in an `actor GameSocket` that exposes an `AsyncStream<ServerMessage>`. No third-party library needed.
- **Messages:** `enum ServerMessage: Decodable` / `enum ClientMessage: Encodable`, decoded by `type`, with `Codable` structs mirroring `PlayerDTO` / `GameStateOut`.
- **Keep-alive:** the server has no heartbeat. Mobile networks and NATs drop idle sockets, so the client should `sendPing` every ~20s. uvicorn answers ping frames automatically, so no server change is needed.
- **Backgrounding is the main mobile risk.** iOS suspends the app, and its socket, seconds after it leaves the foreground. On return to the foreground (`scenePhase == .active`), reconnect and send `REJOIN_ROOM`. That works inside the 30/60s grace window. Past it, show "You were disconnected" and offer a rematch.
- **Network changes:** use `NWPathMonitor` to reconnect when switching Wi-Fi ↔ cellular.
- **Your-turn alerts while the app is closed** need server work: store APNs device tokens and send a push on turn change. That's the path to Live Activities later. Out of scope for v1 unless we want async games.

**Server issues worth fixing (they affect web too):**
- **No turn check on moves:** `GAME_UPDATE` applies the move as whoever's turn it is, without checking the sending socket owns that seat. A modified client could move out of turn.
- **Client-driven timer:** a timer expiry only happens when some client sends `TURN_COMPLETE`. If every client is backgrounded (likely on iOS), the timer never fires. A server-side turn timer would fix this.
- **Rooms live in memory (`ROOMS`):** a deploy or restart drops live games. That's fine for now, but worth knowing.
- **Room codes go up to 100000:** the join field needs up to 6 digits.

## iPad (v1)

- **Universal app, one codebase.** Switch layouts on the horizontal size class / available width, *not* on `UIDevice.idiom`. Split View, Slide Over and Stage Manager can hand an iPad a compact (phone) width.
- **Navigation:** `TabView` with `.tabViewStyle(.sidebarAdaptable)`. That gives a floating tab bar at the top on iPad that can expand into a sidebar, and the normal bottom tab bar on iPhone.
- **Home/setup:** mode list and setup form side by side (`NavigationSplitView`-style). On iPhone, setup is a pushed screen.
- **Game, landscape:** board on the left at full height (~760pt, so 8×8 ≈ 90pt tiles and 12×12 ≈ 58pt), sidebar on the right with all 4 players, turn/timer, a live score chart, and controls. This matches the web's `md+` sidebar.
- **Game, portrait:** player strip across the top (4 columns), board full width (~770pt), controls at the bottom.
- **No pinch-to-zoom needed on iPad** at any board size.
- **Extras to support:** pointer hover states on tiles (trackpad), keyboard shortcuts (arrow keys + space to place), and every orientation.

## Tile feel: animation, sound, haptics (the ASMR layer)

This layer is a priority, so it gets its own spec. The canvas has an interactive "Tile feel" artboard.

**Current web behavior to match** (`game-board.tsx`, `game-tile.tsx`):
- **Place, no shape:** the tile spins 1 full turn over **360ms** with **ease-out cubic** (`1 − (1 − t)³`), and `button.mp3` plays.
- **Shape formed:** each corner tile of each new shape spins **2 × (number of shapes formed this move)** turns. Turns add up when a tile is a corner of several new shapes. Duration is **360ms per turn**, and `spin.mp3` plays. Online play also draws the outline (`enqueueShapeDrawAnimations`).
- **Flip:** a horizontal flip (`scaleX` 1 → 0 → 1, 320ms per flip) exists. Use `rotation3DEffect(.degrees(...), axis: (0, 1, 0))` for a real 3D flip on iOS.

**SwiftUI implementation sketch:**
- **Tile angle:** each tile keeps a cumulative `rotation` (degrees). A spin adds `360 × turns` inside `withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.36 × turns))`. Never reset the angle to 0. Keeping it cumulative avoids a snap-back frame.
- **Multi-step sequences:** use `KeyframeAnimator` (e.g. scale-pop + spin + settle, or flip-then-spin). Keep each tile's animation state in the tile view so 144 tiles don't re-render the whole board.
- **Shape fill (keep this):** a translucent pane in the shape owner's color fills the formed square/diamond, about 10–14% opacity under a solid outline. It fades in as the corner spins settle and stays while "Shapes on" is enabled.
- **Outline draw:** two `trim` animations running out from the tapped corner in opposite directions, meeting at the far corner over ~1–1.5s.
- **Frame rate:** set `CADisableMinimumFrameDurationOnPhone = YES` in Info.plist. Without it, iPhone ProMotion screens cap custom animations at 60Hz. With it, spins run at 120Hz, which makes a big difference to the "smoothness" feel.

**Sound:**
- **Engine:** `AVAudioEngine` with preloaded buffers, not `AVAudioPlayer`, for low latency (<10ms) and overlapping sounds.
- **Variation:** vary pitch slightly (±3–5%) and volume per tap, so repeated placements don't sound robotic. This is a big part of the ASMR quality.
- **Audio session:** use `.ambient`. It mixes with the user's own music and respects the silent switch, which suits a relaxing game.
- **Volume controls:** separate toggles/volumes for sound effects and music (already in the wireframes).

**Haptics:**
- **Synced with sound:** Core Haptics AHAP patterns, played in time with the sound.
  - Place: one crisp transient (sharpness ~0.6, intensity ~0.5).
  - Shape: a short rising ramp + transient on completion, scaled by shapes formed / multiplier.
  - Multiplier increase: a distinct double tap.
- **Fallback:** `.sensoryFeedback(.impact(weight: .light), trigger:)` where a full pattern is overkill.
- **Toggle:** in settings and in the in-game menu. Haptics also follow the system setting automatically.

**Accessibility:**
- **Reduce Motion:** replace spins with a quick fade/scale. Keep sound and haptics, since they carry the feel.
- **VoiceOver:** announce "Blue scored a 4×4 square, plus 16".

## Optional third-party packages (SPM)

Keep the dependency list small. None of these are needed for the wireframe phase.

| Package | Use | Verdict |
| --- | --- | --- |
| Pow (EmergeTools/Pow) | Ready-made "change effects" (shine, sparkle) for scoring moments | Nice-to-have. The core spins should be hand-built to match the spec |
| lottie-ios (airbnb) | Designer-made animations (victory, onboarding) | Only if we get Lottie assets |
| GoogleSignIn-iOS | Parity with web Google login | Needed when auth lands |
| Starscream | WebSocket | Not needed: `URLSessionWebSocketTask` covers it |

## Proposed baseline

- **Language/UI:** Swift 6, SwiftUI, Observation (`@Observable`).
- **Deployment target:** iOS/iPadOS 18+. Revisit when we ship.
- **Structure:**
  - `SquareOffCore` (Swift package): pure game logic (port of `board-logic.ts` / `game-move-engine.ts`). No UI imports, unit tested against fixtures from the TS/Python implementations.
  - `SquareOffNet`: `GameSocket` actor, message `Codable`s, REST clients (matcher, auth, games).
  - `SquareOffUI`: design tokens, `TileView` + animation/sound/haptics engine, `PlayerCard`, charts.
  - App target: screens, navigation, iPhone/iPad layouts.
- **Design tokens** (from the web app): player colors `#0583D2` blue, `#FF3131` red, `#50C878` green, `#EE8329` orange. Dark ground around `#121219`. Display font Grapple (bundle `grapple.ttf` once the license is confirmed; wireframes use Chakra Petch as a stand-in). Body text in SF Pro.

## Mobile design decisions (see wireframes)

1. **Tab bar:** Play · Learn · Profile. On iPad it's a top tab bar that can become a sidebar.
2. **A game is a `fullScreenCover`:** pause/leave goes through a bottom sheet with detents.
3. **Board sizing:** 8×8 on a 390pt-wide phone gives ~41pt tiles + 4pt gaps (45pt pitch). If the tap area covers the gap, it meets Apple's 44pt guideline, so no zoom is needed. 10–12 boards give ~32–26pt tiles on iPhone and need pinch-to-zoom or tap-then-confirm. iPad needs neither.
4. **Thumb zone (iPhone):** scores and timer at the top, board in the middle, controls at the bottom.
5. **Online:** Quick match / Join by code / Create room / Browse lobby mirror `matcherAPI`. Invite with `ShareLink` + universal link to `/guest/:roomCode`.
6. **Accounts:** App Review guideline 4.8 requires Sign in with Apple when Google login is offered. The server already has an Apple key and `docs/todo/APPLE_OAUTH.md`.

## Decisions

**Decided (2026-10-17)**
- **CPU moves:** from the server via `POST /cpu_move`, for all 6 levels with the web's numbering.
- **Sign-in:** password + guest for v1. Guest play needs no account: it uses the server's seeded guest IDs from `GET /guests`, exactly like the web. Apple / Google / GitHub buttons are placeholders until Sign in with Apple works on the web.
- **Theme:** dark only.
- **Project:** Xcode project generated by XcodeGen (`project.yml`) + a local SPM package (`SquareOffKit`). iOS 18+.
- **Tests:** Swift Testing for rules, networking and the app's game session. Live contract tests run against the local docker-compose server (opt-in with `SQUAREOFF_LIVE_API=1`). Snapshot tests come next.
- **Environments:** a mock backend by default; the local docker server (`https://localhost:8002/api`) via Profile › Developer.
- **Universal iPhone + iPad**, REST/WebSocket parity with the web, the translucent shape fill, and the web's tile spin timings.

**Decided (2026-10-19), supersedes the CPU and sign-in lines above**
- **CPU moves are computed on device** for levels 1, 2, 4, 5 and 6 (`SquareOffCore/CPU/CPUStrategy.swift`, a line-for-line port of `model.py` including its tie-break quirks; tests assert candidate sets, seeded determinism and full CPU-vs-CPU games on 6×6–12×12). Level 3 (CNN) stays online-only and is greyed out in setup; `CPULevel.offlineFallback` maps it to Max-Min-Optimal if it ever reaches a session.
- **No server calls in the v1 game flow.** The app target links only `SquareOffCore`. `GameSession` takes a `CPUMoveProvider` and a `GameRecorder`; the server-backed versions come in a later pass.
- **Guest only.** Sign-in is a static mockup reached from Profile. No password login, no backend switch.

**Offline CPU play: originally deferred (2026-10-17), now done (see above). Sync queue still open.** It's feasible but needs two things the web doesn't have:
1. **On-device CPU.** Port levels 1, 2, 4–6 (see the CPU section). Level 3 (CNN) stays online-only, or later moves to Core ML.
2. **A sync queue.** Record the game locally, then on reconnect replay it to the server: `POST /start`, then each `POST /{id}/turns` in order.
   - **Duplicates on retry:** the server has no idempotency keys, so a retry after a timeout can duplicate turns. Fix: an `Idempotency-Key` header, or one batch endpoint for a whole finished game.
   - **Wrong dates:** turns get the server's timestamp at sync time, which skews stats by date. Fix: accept client `played_at`.
   - **Guest ownership:** guest games are recorded under shared guest IDs, so syncing them adds little.
- **Design now so it slots in later:** CPU moves and turn recording sit behind the `SquareOffAPI` protocol, so an `OfflineCPU` + `SyncQueue` can be added without touching screens.

**Server findings from running the local stack**
- `/cpu_move` with `cpu_type: "cnn"` returns 500 (`NameError: CNN_MODEL`), so Level 3 is broken on web too. The app falls back to a random move and shows a notice. The live test records it as a known issue.
- `/cpu_move` needs each player's existing `squares` / `diamonds` (`row`, `col`, `num`, `size`), or the server re-counts old shapes when it scores candidates.
- The web sends explicit `null`s (e.g. `"cpu_type": null`), and the iOS encoders do the same.
- All routes live under `/api`. Local dev serves HTTPS with an mkcert certificate on port 8002.

**Still open (before launch)**
- Fix the server online issues (turn ownership check, server-side turn timer)?
- Session length: refresh tokens / longer mobile sessions?
- Resume games after the app is killed?
- "Your turn" push notifications (APNs) in v1?
- Spectator mode in v1?
- Licenses: Grapple font, the music, the SFX (`button.mp3` / `spin.mp3` are bundled from the web for now).
- Analytics on iOS?
- Monetization: StoreKit for any paid features. Don't ship the crypto-support modal.
