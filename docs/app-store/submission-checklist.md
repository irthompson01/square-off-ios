# Submission checklist — Square Off 1.0.0

## In the repo (done on `feature/web-parity`)
- [x] Entitlements: Sign in with Apple; applinks + webcredentials for square-off.com and www.square-off.com; Debug twin with `?mode=developer` really used by Debug.
- [x] `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption = false`, category Board games, opaque 1024 icon.
- [x] Account deletion (two taps), forgot/reset password, email verification, feedback form.
- [x] `make release-check` passes (versions, entitlements incl. the www entries and no developer mode, icon alpha, privacy manifest).
- [x] Metadata drafted in `metadata/`, review notes, App Privacy answers, age rating, content rights, TestFlight notes (this folder).
- [x] `scripts/store-screenshots.sh` produces the 6.9" iPhone and 13" iPad sets.

## Web (deployed; re-checked 2026-11-22)
- [x] https://square-off.com/privacy and /support live (required URLs).
- [x] `feature/guest-claim` deployed (`deployments/2026-11-15_guest-history-claim/`): logging in on a device that played as a guest brings those games along; until then the app's claim call 404s quietly.
- [x] https://square-off.com/turnstile renders the widget (native sign-up depends on it).
- [x] AASA lists `/verify-email`; Apple's CDN refreshed (`https://app-site-association.cdn-apple.com/a/v1/square-off.com`).

## Owner only
- [x] Licences settled (owner confirmed 2026-11-22): Grapple font, `harmonies.mp3`, `button.mp3`, `spin.mp3` (`content-rights.md`).
- [ ] Developer portal: App ID `com.novastrada.squareoff` with Sign in with Apple + Associated Domains.
- [x] App Store Connect: app record created as "Square Off: Battle of Shapes" (SKU `squareoff-ios`). Still to set: category Games › Board + Strategy, pricing Free, availability.
- [x] App Store Connect API key (App Manager) → `keys/AuthKey_<id>.p8` (gitignored); `make testflight ASC_KEY_ID=… ASC_ISSUER_ID=…`. Export signs manually with the "Square Off App Store" profile (see `ExportOptions.plist`).
- [x] Build 1.0.0 (1) uploaded 2026-11-21 (tag `v1.0.0-b1`).
- [x] Demo account created on the website, verified, with a few games played (so the reviewer's Stats tab isn't empty).
- [ ] Demo credentials and contact details entered in App Review Information (never in this public repo; `review-notes.md` keeps its placeholders).
- [x] TestFlight internal group created.
- [ ] `testflight-what-to-test.txt` run on an iPhone and an iPad.
- [x] App Review functionality recording made per `review-recording.md` (2026-11-22, kept in the gitignored `recordings/` folder).
- [ ] Recording attached under App Review Information, or its private URL added to the review notes.
- [x] Version set to 1.0.0 and build 1.0.0 (1) selected (2026-11-22).
- [ ] Version page: screenshots (both sets), metadata from `metadata/en-US`, App Privacy (`app-privacy.md`), age rating (`age-rating.md`), Content Rights, review notes, the TestFlight build; "Manually release this version"; submit.

## Build discipline
- `MARKETING_VERSION` stays 1.0.0 until release; `make bump` (build +1) before every upload, never reuse a build number; tag uploads `v1.0.0-bN`.
- Submit the exact TestFlight build that passed the checklist; no re-archive for submission.
