# App Review screen recording: what to do

A functionality video for App Review (attached under App Review Information, or linked from the
notes). It is not the store App Preview: no music, no captions, just the app being used. Aim for
4–6 minutes. One continuous take is fine; if a scene goes wrong, redo that scene and stitch in iMovie.

This repo is public, so the addresses are named by role here and kept out of the file:

| Role | What it is |
| --- | --- |
| **Demo account** | The verified account with games played that the reviewer gets. Never delete it. |
| **Rehearsal address** | Throwaway inbox for the off-camera practice run of scenes 9–10. |
| **Take address** | Throwaway inbox for the recorded sign-up and delete (scenes 9–10). |
| **Mac account** | Your own account, logged in at https://square-off.com on the Mac: the second player. |

The phone is the only screen recorded. The Mac never appears, but the Mac account's username does
(it shows in the room's player list on the phone).

## Part 1: set up (not recorded)

**Phone**

1. If an older build is installed and logged in: Profile › Manage account › Log out. The login is
   kept in the Keychain and survives deleting the app, so log out first.
2. Delete the app, then install build 1.0.0 (1) from the TestFlight app.
3. Open it once, dismiss TestFlight's intro sheet if it shows, and check Profile says "Playing as a guest on
   this device". Do not play a game yet.
4. Mail: both throwaway addresses deliver to your iCloud inbox. Mark everything read and turn on
   the Unread filter, so the only message on screen later is the verification email.
5. Do Not Disturb on, Wi-Fi on, Low Power Mode off, brightness up, portrait lock on.
6. Add Screen Recording to Control Center; long-press it and make sure the microphone is off.

**Mac**

7. Safari at https://square-off.com, logged in with the Mac account. Keep the window ready.
8. Never log in to the Mac account on the phone: the two sides must be different players.

## Part 2: rehearsal (not recorded)

Run scenes 9 and 10 once with the **rehearsal address**. You are checking three things:

- The verification email arrives within a minute (look in Junk if not).
- Tapping the link in Apple Mail opens the app on "Email verified", not Safari. If Safari opens,
  go back to Mail, long-press the link and choose "Open in Square Off"; iOS remembers the choice.
- Delete account ends with the "Account deleted" toast and the old login is refused.

Then reset for the real take: delete the app, reinstall from TestFlight, open it once, confirm
Profile shows the guest state, and force-quit.

## Part 3: the take

Start Screen Recording, wait for the countdown, go to the Home Screen and open Square Off.

1. **Home and setup (30 s).** Pause on Home for two seconds. Tap **Start game**. On the setup
   screen show **Board**, **Timer** and **CPU level**; pick the smallest board (6 × 6) and Level 3. Tap
   **Start game**.
2. **vs Computer (60–90 s).** Play the game to the end; make at least one square or diamond so the
   score and the multiplier pill change. Midway, open the game menu, tap **How to play**, close it,
   carry on. At the results sheet tap **Home**. Finish this one rather than leaving: it is the
   guest game that scene 7 moves into the demo account.
3. **Level 8 (20 s).** Start game › CPU level 8 (Impossible) › Start game. Make two moves and let
   the opponent answer each (these moves come from the server). Menu › **Leave game** › confirm.
4. **Pass & Play (30 s).** Play › **Pass & Play**, 3 players, rename one seat, change one colour,
   **Start local game**. Play one round so the turn passes through all three. Leave the game.
5. **Online room (60 s).** Play › **Online** › **Create** › **Create room**. Pause on the room
   code, tap **Copy invite link**.
   - Mac: open `https://square-off.com/guest/<code>` using the code on the phone, and join.
   - Phone: the Mac account appears in Players. Tap **Start game**. Play two turns each.
   - Optional: let one turn timer run out to show the timeout handling.
   - Menu › **Leave room** › confirm.
6. **Quick match (30 s, optional).** Phone: Online › **Quick match** › **Find a match**. Mac: Quick
   match with the same board and timer. Show "Match found" and the first move, then leave. Skip
   this scene if a stranger gets matched instead.
7. **Log in with the demo account (45 s).** Profile › **Log in**, enter the **demo account** email
   and password, Log in. Pause on the "Logged in" toast: it says the games played here as a guest
   are now in the account. Tap **Game stats**, scroll Statistics and Game history, open one game,
   tap **Next move** a few times, close the replay.
8. **Sign in with Apple (15 s).** Profile › Manage account › **Log out**. Tap **Log in** ›
   **Continue with Apple** and complete the sheet (choose Hide My Email if it asks). When the
   profile shows, log out again.
9. **Create a password account (45 s).** Profile › **Create account**. Type a username (3+
   characters), the **take address**, and a password (8+ characters). Wait for the **Anti-bot
   check** widget to finish, then submit. Pause on "Check your email". Switch to Mail, open the
   "Verify your Square Off email" message, tap the link. The app opens on "Email verified"; tap
   **Log in** and log in with the take address.
10. **Delete account (30 s).** Still on the take-address account: Profile › Manage account ›
    **Delete account** › **Continue** › **Delete account**. Pause on the "Account deleted" toast.
    Then Profile › Log in with the same address and password to show it is refused.
11. **Feedback (15 s).** Profile › **Send feedback**. Subject "App Review recording", a one-line
    message, **Send message**. Pause on "Thanks — your message was sent." (This is a real
    submission to the production inbox.)
12. **Preferences (15 s, optional).** Profile › Preferences: toggle Sound effects, Haptics and
    Starfield off and on.

Stop the recording from Control Center.

Optional iPad clip: install the same build from TestFlight on the iPad, start a vs Computer game,
rotate the device, then pull in Split View at one-third width.

## If something goes wrong

- **No claimed-games line in scene 7** (toast only says "Welcome back."): the guest game was not
  finished, or the phone was not a guest. Log out, finish one vs Computer game, and redo the scene.
- **Email link opens Safari in scene 9:** use the long-press fix from the rehearsal and redo from
  the Mail step; the same link still works until it has verified the account.
- **Scene 9 or 10 needs a full redo after the account exists:** the take address is used up.
  Create another Hide My Email address rather than reusing it.
- **Resend limit:** an account gets at most three verification links an hour.

## Do not show

- The admin app, Xcode, the simulator, or any mock/local backend.
- The Mail inbox beyond the verification message, or any personal address.
- The demo account's password in clear text (the field is masked; do not paste it from Notes on
  camera).

## After recording

- Watch it once: check the Mail frames in scene 9 and that no notification slipped through.
- Trim the ends and export at the original size.
- Attach it under App Review Information, or upload to a private link and put the URL in the
  review notes under the demo account line.
- Tick the recording row in `submission-checklist.md`.
