# iOS plan: puzzles, friends and turn-based games

Written 2026-11-27. Nothing here is built yet.

The web repo owns the API and data for both features and ships each phase first. Its two specs are `docs/todo/PUZZLES.md` (Track A) and `docs/todo/FRIENDS_AND_TURN_BASED.md` (Track B) in the web repo; they are the contract. This document says what iOS builds, in which release, and what each piece waits for.

## Decisions already made

| Topic | Decision |
| --- | --- |
| Order | Puzzles first, then friends, then turn-based games with push. |
| Daily puzzle | Same puzzle for everyone, personal streak, shareable result. Retries allowed, tries counted. Answers checked on device. No leaderboard. |
| Finding friends | Exact username, or an "add me" code and link. No email lookup. |
| Usernames | Every account gets a valid handle; handles are editable with a cooldown. |
| Turn-based timeout | The player who runs out of time forfeits, after a reminder. |
| Alerts | iOS does not ship turn-based games until Apple push works. |

## Release grouping

| Release | Feature | Waits for (web phase) |
| --- | --- | --- |
| 1.1 | Puzzles and the daily puzzle | A0 to start, A1 for the daily, A3 for launch content, A4 for progress sync |
| 1.2 | Friends, presence, live challenges | B0–B3 |
| 1.3 | Turn-based games and push notifications | B4a–B6 |

## 1.1 Puzzles

**What to build**

- **Puzzle model and decoder** in `SquareOffCore`, matching the shared JSON format (snake_case, 0-based `[row, col]`, slots 1 and 2). Skip puzzles with an unknown `schema_version` or goal type.
- **Parity test:** replay every bundled puzzle through the Swift engine and compare with its `expect` block (scores, multipliers, shape counts per step). This is the same guarantee the rulebook demos get from `RulebookDemoTests`.
- **Position setup:** replay `setup` placements through `place(at:by:)`, as `DemoBoardView` does. Do not build a `Game` from a bare board: shapes already on it would score again.
- **`PuzzleSession`** conforming to `GamePresenting` (`Features/Game/GamePresenting.swift`), so `BoardView` and the game chrome are reused. Add protocol-extension defaults for the online-only members first; today only `reconnect()` has one.
- **Puzzle player UI:** prompt, hint, wrong-move feedback (show the opponent's reply, then reset), show solution, retry, solved state.
- **Where it lives:** the Learn tab gains Lessons and Daily next to Rules; a daily card on Home.
- **Content:** lesson packs are bundled in the app (copied from the web repo at a pinned commit by a sync script) and refreshed from the catalogue when `content_version` changes. The daily is fetched and cached; future dailies are never bundled.
- **Progress:** attempts are queued on device and sent in batches, so puzzles work offline. Guest progress follows the account on login, like guest games do.
- **Streak and share:** streak from the server when online, shown from cache otherwise; share text with puzzle number, tries and streak.
- **Daily reminder:** a local notification at a time the player picks. This needs notification permission but not Apple push.
- **Deep link:** `/puzzles/daily` and `/puzzles/<id>` in `App/DeepLink.swift`, `AppModel.open`, and `DeepLinkTests`. The web side adds `/puzzles/*` to the AASA file.
- **Mock backend and screenshots:** puzzle endpoints in `MockSquareOffAPI`, a `-demoScreen puzzle` launch argument, and a store screenshot.

**What exists to build on**

- `Game` / `Board` / `preview`, move-list replay, `SplitMix64`.
- `MoveEvaluator` for one-move feedback. It looks one move ahead only, which is why multi-move puzzles carry scripted replies.
- `RulebookDemo` (`Features/Learn/RulebookDemos.swift`): already a `setup` + `moves` format.
- `LocalGameStore`'s Codable snapshot pattern, for the attempt queue and cached daily.

## 1.2 Friends

**What to build**

- **Username editing** in Profile (new optional `display_name` in the profile payload).
- **Friends tab:** friends with online dots, incoming and outgoing requests, add by username, share my "add me" link, block and report.
- **Inbox store:** one polled endpoint while the app is in the foreground. It drives the tab badge and is also what marks the player online. Stop polling in the background.
- **Live challenge:** pick a friend from the waiting room; accepting hands a room code to the existing `RoomCoordinator` join flow.
- **Deep link:** `/friends/add/<code>` (confirm before sending the request).
- **API surface:** new methods on `SquareOffAPI`, DTOs, mock state, `SpyAPI` coverage and captured fixtures, following the existing parity conventions.

**Tab layout (open question):** Play · Learn · Friends · Profile, with turn-based games listed inside Friends in 1.3.

## 1.3 Turn-based games and push

**What to build**

- **`AsyncGameSession`** conforming to `GamePresenting`, backed by REST instead of the socket. The game arrives as participants plus a turn list in the replay shape, so the board is rebuilt with the same logic `ReplayView` uses. Moves are confirmed, sent with the current ply, and the server's answer replaces local state.
- **A third session slot** in `AppModel` beside `activeGame` and `activeOnlineGame`, and copy for "leave" and game-over that fits a game lasting days.
- **Games list:** Your move, Their move, Finished, with deadline countdowns; challenge sheet (friend, board, pace, who starts); resign and rematch.
- **Polling:** every few seconds while the game screen is open and the opponent is online, slower otherwise.
- **Push notifications:**
  - Push capability on the App ID, `aps-environment` in both entitlements files, and `make release-check` updated to expect it.
  - The "Square Off App Store" provisioning profile must be regenerated after the capability is added (the export signs manually with it).
  - Permission prompt at a sensible moment (first challenge sent or accepted), device-token registration, token removal on logout.
  - Tap routing through `DeepLink` to `/game/<id>` or Friends; badge count from the inbox.
  - Settings toggles per notification category.
- **Deep link:** `/game/<id>`.

## Owner actions

1. Apple push key (`.p8`) for the server, and the Push Notifications capability on the App ID.
2. App Privacy answers and `PrivacyInfo.xcprivacy` reviewed when friends and push tokens arrive; review notes updated to describe block and report (guideline 1.2).
3. Age rating questionnaire re-checked once players can find and challenge each other.

## Testing approach

- Core: decoder and parity tests for every bundled puzzle; session tests for wrong move, scripted reply and solved state.
- Net: DTO decoding against fixtures captured from the docker server after each web phase (`scripts/capture_rest_fixtures.sh`).
- App: `SpyAPI` tests for the attempt queue, inbox polling, challenge accept and the move/conflict path; deep-link tests for each new path.
- Device: one pass on the phone per release, including a push delivered to a backgrounded app and a universal link from Mail.
