# App Review screen recording

A short functionality video for App Review (attached under App Review Information, or linked from
the notes). It is not the store App Preview: no music, no captions needed, just the app being used.
Target 4–6 minutes. Record only after the web release (guest-history claim) is live, so the login
scene shows the claimed games.

## Before recording

- Production build from TestFlight on the phone (not an Xcode debug build, no `-backend mock`).
- Demo account exists, is verified, and has a few games played (same one as `review-notes.md`).
- A fresh throwaway email address for the sign-up scene, open in Mail on the phone.
- Second player ready: the web client at https://square-off.com on the Mac, logged out (guest), so the
  invite link and quick match have someone to meet.
- Phone: Do Not Disturb on, Wi-Fi on, brightness up, portrait, Low Power Mode off.
- Start from a clean install (delete the app, reinstall from TestFlight) so Home shows the first-run
  state and the account is a guest.
- Recording: Control Center › Screen Recording (microphone off). One continuous take is fine;
  trim the ends afterwards. If you need several takes, keep each scene one take and stitch in iMovie.

## Scenes, in order

1. **Home and setup (30 s).** Open the app, pause on Home. Tap Start game. Show the board, timer and
   level controls, change the level to 3, Start game.
2. **vs Computer (45 s).** Play six or so moves. Make one square or diamond so the score and the
   multiplier pill change. Open the game menu and show How to play, close it, resume. Finish or
   leave the game (menu › Leave › confirm).
3. **Level 8 (20 s).** New game, Level 8 (Impossible), 8×8. Make two moves so the server-backed
   opponent answers. This covers the "our own server, no third-party AI" line in the notes.
4. **Pass & Play (30 s).** Play › Pass & Play, 3 players, rename a seat, pick a colour, Start local
   game, play a round so the turn passes between players.
5. **Online room (60 s).** Play › Online › Create room. Show the code and Copy invite link. On the Mac,
   open the invite link in Safari, join as a guest. Back on the phone the seat appears; Start game.
   Play two turns each. If you can, let one turn timer run out to show the timeout handling.
6. **Quick match (30 s, optional).** Phone: Online › Quick match › Find a match. Mac: Quick match
   with the same board and timer. Show the match form and the first move. Skip if the lobby is busy.
7. **Log in and claimed games (45 s).** Profile › Log in with the demo account. The toast says the
   games from this device were added. Open Stats and Recent games, open one replay, step through
   a few moves, close.
8. **Sign in with Apple (15 s).** Log out, then tap Sign in with Apple and go through the sheet (Hide
   My Email is fine). Shows guideline 4.8 compliance. Log out again.
9. **Create a password account (45 s).** Profile › Create account with the throwaway address. Show
   the Turnstile widget rendering under the form and submit. Land on "Check your email". Switch to
   Mail, tap the link, the app opens on the verified screen, tap Log in, log in.
10. **Delete account (30 s).** On that new account: Profile › Manage account › Delete account, both
    confirmations. Then try to log in with it to show it is gone (guideline 5.1.1(v)).
11. **Feedback (15 s).** Profile › Send feedback, type a line, send, show the confirmation.
12. **Settings and iPad (optional, 30 s).** Toggle sound and haptics, switch appearance. If you record
    an iPad clip, show rotation and Split View at one third width in a game.

## Do not show

- The admin app, Xcode, the simulator, or any mock/local backend.
- Real personal email addresses other than the demo and throwaway ones.
- Room codes you intend to keep open after recording (they expire anyway).

## After recording

- Trim, check nothing sensitive is on screen (Mail inbox in scene 9), export at the original size.
- Upload to a private link (or attach in App Review Information) and put the URL in the review notes
  under the demo account line.
- Tick the recording row in `submission-checklist.md`.
