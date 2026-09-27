# Store Release Guide (Google Play & App Store)

Everything the app needs **outside this repository** before it can pass review:
backend endpoints, files on `jodealz.online`, console settings, store forms,
and the release checklist. Code-side compliance work is already done in the app.

---

## 1. Backend (`D:\Projects\Personal\JoDeals`) — implemented, deploy it

These changes are made in the website repo (uncommitted, alongside your own
work there). Deploy them together with this app version.

| File | Change |
|---|---|
| `public_html/includes/social-token-verifier.php` | **New.** Verifies Google/Apple ID tokens (RS256 signature against the provider's JWKS, `iss`, `aud`, `exp`). JWKS cached for 1 h in the system temp dir. |
| `public_html/api/v1/auth/social.php` | Requires `id_token`; identity (`sub`, email) comes only from the verified token. Matches users by `provider + sub`, then by verified email. Facebook removed (the app never used it). Old app builds without a token get `ID_TOKEN_REQUIRED` + "please update". |
| `public_html/api/v1/auth/delete-account.php` | **New.** `POST {"confirm":true}` with the session token. Deletes the customer's account and personal data (cart, saved deals, favourite categories, notifications, device tokens, sessions, login history, password resets, tour progress, roles, referral code, profile photo file) in one transaction, unlinks the device from the person, ends the session. Business/admin accounts get `409 CONTACT_SUPPORT`. |
| `public_html/api/register-device.php` | The user is taken only from a valid, active session token (a body `user_id` was trusted before — anyone could receive another user's pushes). Partial updates no longer wipe the stored FCM token/device fields. iOS devices without analytics consent are no longer recorded as "Android". Removed a call to the non-existent `JWTHelper::verify()`. |
| `public_html/api/update-fcm-token.php` | Same session-token fix; the old `JWTHelper::verify()` call made every token refresh from the app fail with a PHP fatal error (HTTP 500). |
| `public_html/api/update-device-preferences.php`, `register-device.php`, `config/db.php` | New devices default to `marketing_enabled = 0` (promotional pushes are opt-in, App Store 4.5.4). Existing rows keep their value. |

Optional configuration (environment variables on the server):
`GOOGLE_OAUTH_AUDIENCES` (comma-separated OAuth client IDs accepted as `aud`;
default: the Web client `724842455682-9277…`) and `APPLE_CLIENT_IDS`
(default: `com.jodealz.app`). PHP needs the `openssl` and `curl` extensions and a
CA bundle (standard on cPanel hosting).

### Still to do on the backend (optional)
- **Apple token revocation on account deletion.** Apple asks apps to revoke Sign in
  with Apple tokens when an account is deleted. This needs your Apple
  "Sign in with Apple" private key (.p8) to create a client secret, so it isn't wired
  up yet.
- **Existing marketing opt-ins.** Devices registered before this change still have
  `marketing_enabled = 1`. If you want everyone to re-consent, run
  `UPDATE device_notification_preferences SET marketing_enabled = 0;` once.

### Push payloads
`data.url` in FCM messages must be a `https://jodealz.online/...` URL or a
relative path; other hosts are ignored. Android notifications use channel
**`jodealz_notifications_v2`** (it has the custom sound) — if the server sets
`android.notification.channel_id`, update it.

---

## 2. `.well-known` files (already in `public_html/.well-known/`)

- **`assetlinks.json`** — present for `com.jodealz.app` with two SHA-256
  fingerprints. Make sure they are the **Play App Signing** key and your upload key
  (Play Console → *Test and release → App integrity*). Verify on a device with
  `adb shell pm get-app-links com.jodealz.app`.
- **`apple-app-site-association`** — present for team `9JA89QQL32`
  (now also set as `DEVELOPMENT_TEAM` in the Xcode project). It covers
  `/deal.php*`, `/profile.php*`, `/category/*` and `/index.php*`; add other paths
  (e.g. `/deals.php*`, `/`) if those links should open the app too. Serve it with
  `Content-Type: application/json` and no redirects.

---

## 3. Console setup

### Google Cloud / Firebase (project `jodeals-eaec4`)
1. **Create an iOS OAuth client** (APIs & Services → Credentials → OAuth client ID → iOS,
   bundle `com.jodealz.app`). Put its client ID in `ios/Runner/Info.plist` →
   `GIDClientID`, and its *reversed* client ID in `CFBundleURLSchemes`.
   The values currently there belong to a different Google Cloud project
   (`13492427447`); tokens issued for it may be rejected by the server client.
2. Add the **Play App Signing** SHA-1 and SHA-256 to the Firebase Android app
   (Project settings → Your apps). Without them Google Sign-In fails in Play builds.
3. Upload the **APNs Auth Key (.p8)** to Firebase → Project settings → Cloud Messaging → Apple app.
4. Enable **Crashlytics** in the Firebase console.
5. Restrict the Firebase API keys (Google Cloud → Credentials): Android key to
   `com.jodealz.app` + SHA-1, iOS key to bundle `com.jodealz.app`.

### Apple Developer
1. Identifier `com.jodealz.app` → enable **Push Notifications**, **Associated Domains**,
   **Sign in with Apple**.
2. The Xcode project already uses team `9JA89QQL32`; check Signing & Capabilities shows no errors.
3. Sign in with Apple → Services ID/keys only if the website also offers Apple login.

### Google Play Console
1. Enroll in **Play App Signing**; keep the upload keystore + `android/key.properties` out of git.
2. If the developer account is a *personal* account created after 13 Nov 2023:
   run a **closed test with ≥ 12 testers for 14 consecutive days** before applying for production.

---

## 4. Build commands

CI builds run on Codemagic (`codemagic.yaml`, setup in `docs/CODEMAGIC.md`). Local equivalents:

```bash
# Android (upload the .aab; upload build/symbols to Crashlytics via Firebase CLI if desired)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols

# iOS (on a Mac with the current Xcode)
cd ios && pod install && cd ..
flutter build ipa --release --obfuscate --split-debug-info=build/symbols
```

Obfuscated Dart stack traces are symbolicated with
`firebase crashlytics:symbols:upload --app=<APP_ID> build/symbols`.

---

## 5. Store privacy answers

Keep these in sync with `ios/Runner/PrivacyInfo.xcprivacy` and the privacy policy.
Nothing is sold, nothing is used for third-party advertising, **no tracking** (no ATT prompt needed).

| Data | Collected | Linked to user | Optional | Purpose |
|---|---|---|---|---|
| Name, email, phone, address | Yes (account) | Yes | Account is optional (guest mode) | App functionality, account management |
| Photos | Yes (uploads) | Yes | Yes | App functionality |
| Precise location | Only when a nearby-deals feature asks | Yes | Yes | App functionality |
| Device ID (Android ID / IDFV), push token | Yes | Yes | No (push) | App functionality; analytics if opted in |
| App interactions (deal/category views) | Only with usage-data opt-in | Yes | Yes | Analytics, personalization |
| Crash logs / diagnostics | Yes (Crashlytics, error logs) | Yes | No | App functionality (stability) |
| Performance (page load time) | Only with opt-in | Yes | Yes | Analytics |

Play Data safety extras: data encrypted in transit **Yes**; users can request
deletion **Yes** (in-app + web URL from §1.2); Advertising ID **not used**.

---

## 6. App Review notes (paste into App Store Connect / Play "App access")

> JO-Dealz is a deals app for Jordan. Native features beyond the website:
> native sign-in (email, Sign in with Apple, Google) with Face ID / fingerprint
> unlock; native Profile, Settings and in-app **account deletion**
> (Profile → Delete Account); a native, offline-capable deals feed with search and
> category filters (opened from the Deals listing, cached in a local database);
> an offline screen that shows cached deals without a connection; push
> notifications with per-category preferences; camera/photo upload; Arabic and
> English with full RTL support.
>
> Demo account: `<reviewer email>` / `<reviewer password>` (a dedicated reviewer
> account, not a real user).

---

## 7. Pre-release checklist

**Both**
- [ ] Leaked password from the old `test_login.json` changed; history purged
- [ ] Backend changes from §1 deployed; sign-in with Google + Apple and account deletion tested against production
- [ ] Privacy policy updated (collection table above, deletion, retention, consent)
- [ ] Reviewer demo account created and entered in both consoles
- [ ] Test on real devices: first launch → onboarding → consent sheet → notification prompt;
      email / Google / Apple login; logout; delete account; push tap (foreground, background,
      killed); deep link cold + warm start; offline mode; camera + gallery upload
- [ ] Crashlytics receives a test crash from a release build

**Google Play**
- [ ] `.aab` built with the commands in §4, signed with the upload key
- [ ] `assetlinks.json` live, `pm get-app-links` shows verified
- [ ] Data safety, content rating, target audience, App access, account-deletion URL
- [ ] Pre-launch report: no crashes, no edge-to-edge warnings
- [ ] Tested on Android 16 (gesture + 3-button nav), a tablet/foldable, and API 24

**App Store**
- [ ] Built with the current Xcode; app launches with the UIScene lifecycle
- [ ] Capabilities enabled on the App ID; APNs key in Firebase
- [ ] `apple-app-site-association` live; Universal Link opens the app
- [ ] App Privacy answers match §5; screenshots for required iPhone sizes
- [ ] Review notes from §6 pasted; TestFlight pass on a physical iPhone
