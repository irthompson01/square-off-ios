# App Review Information › Notes (paste as is, fill the placeholders)

Square Off is a turn-based strategy board game. Everything below can be tried without an account; the demo account is for the signed-in screens.

**Demo account (production):** email `DEMO_EMAIL`, password `DEMO_PASSWORD`. Log in under Profile › Log in. It has played games, so Stats, Replays and Recent games are populated.

**Guest play needs no account.** Play › Vs Computer, Pass & Play and Online all work signed out; guest games are recorded under an anonymous device session so stats continue after signing in on the same device.

**Computer opponents.** Levels 1–6 run on the device. Levels 7 (Grandmaster) and 8 (Impossible) ask our own server at square-off.com for each move and need a network connection; if the server cannot be reached the app falls back to Level 6 on the device and tells the player. No third-party AI service is involved.

**Online rooms.** Play › Online › Create gives a five-digit room code and a share link (https://square-off.com/guest/<code>). On a second iPhone with the app installed the link opens the app directly (universal link); without the app it opens our web client, so phone and browser players share rooms. Quick match pairs two waiting players.

**Sign in with Apple** is offered next to Google, GitHub and email/password (guideline 4.8).

**Creating a password account.** The form is native. Because sign-up requires an anti-bot check (Cloudflare Turnstile) that only renders on our own domain, the small widget under the form is a web view of https://square-off.com/turnstile; nothing else about sign-up or sign-in uses a web view. After submitting, the account is pending until the link in the confirmation email is opened; that link opens the app's verification screen (universal link).

**Account deletion.** Profile › Account › Delete account, two confirmations, then `POST /api/account/delete` removes the account; accounts created with Sign in with Apple re-authorise so the server can revoke the Apple token (guideline 5.1.1(v)).

**Feedback form** (Profile › Send feedback and the in-game menu) posts to our server; a contact email is optional.

**Privacy.** No ads, no purchases, no analytics SDKs, no tracking. Data collected: email, display name, user id (an anonymous id for guests), gameplay records, and feedback text. Privacy policy: https://square-off.com/privacy. Support: https://square-off.com/support.

**Contact for review:** REVIEW_CONTACT_NAME, REVIEW_CONTACT_PHONE, REVIEW_CONTACT_EMAIL.
