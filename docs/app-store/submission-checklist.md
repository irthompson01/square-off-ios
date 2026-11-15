# Submission checklist — Square Off 1.0.0

## In the repo (done on `feature/web-parity`)
- [x] Entitlements: Sign in with Apple; applinks + webcredentials for square-off.com and www.square-off.com; Debug twin with `?mode=developer` really used by Debug.
- [x] `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption = false`, category Board games, opaque 1024 icon.
- [x] Account deletion (two taps), forgot/reset password, email verification, feedback form.
- [x] `make release-check` passes (versions, entitlements incl. the www entries and no developer mode, icon alpha, privacy manifest).
- [x] Metadata drafted in `metadata/`, review notes, App Privacy answers, age rating, content rights, TestFlight notes (this folder).
- [x] `scripts/store-screenshots.sh` produces the 6.9" iPhone and 13" iPad sets.

## Web (deploy `feature/ios-parity-web` first)
- [ ] https://square-off.com/privacy and /support live (required URLs).
- [ ] https://square-off.com/turnstile renders the widget (native sign-up depends on it).
- [ ] AASA lists `/verify-email`; Apple's CDN refreshed (`https://app-site-association.cdn-apple.com/a/v1/square-off.com`).

## Owner only
- [ ] Licences settled: Grapple font, `harmonies.mp3`, `button.mp3`, `spin.mp3` (`content-rights.md`).
- [ ] Developer portal: App ID `com.novastrada.squareoff` with Sign in with Apple + Associated Domains.
- [ ] App Store Connect: app record (name availability; fallback "Square Off: Battle of Shapes"), SKU, primary language, category Games › Board + Strategy, pricing Free, availability.
- [ ] App Store Connect API key (App Manager) → `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`; `make testflight ASC_KEY_ID=… ASC_ISSUER_ID=…`.
- [ ] Demo account created on the website, verified, with a few games played; credentials into `review-notes.md` placeholders and App Review Information.
- [ ] TestFlight internal group; run `testflight-what-to-test.txt` on an iPhone and an iPad.
- [ ] Version page: screenshots (both sets), metadata from `metadata/en-US`, App Privacy (`app-privacy.md`), age rating (`age-rating.md`), Content Rights, review notes, the TestFlight build; "Manually release this version"; submit.

## Build discipline
- `MARKETING_VERSION` stays 1.0.0 until release; `make bump` (build +1) before every upload, never reuse a build number; tag uploads `v1.0.0-bN`.
- Submit the exact TestFlight build that passed the checklist; no re-archive for submission.
