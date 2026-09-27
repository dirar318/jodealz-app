# Store Release Guide (Google Play & App Store)

Everything the app needs **outside this repository** before it can pass review:
backend endpoints, files on `jodealz.online`, console settings, store forms,
and the release checklist. Code-side compliance work is already done in the app.

---

## 1. Backend changes (jodealz.online)

### 1.1 Verify social login tokens — `POST /api/v1/auth/social.php` (Critical)

The app now sends a signed identity token. The server **must verify it and take
the user's identity only from the verified token**. The plain `email` /
`provider_id` fields are informational and must not be trusted, or anyone can
sign in as any user by posting their email.

Request body (JSON):

| Field | Google | Apple |
|---|---|---|
| `provider` | `"google"` | `"apple"` |
| `id_token` | Google ID token (JWT) | Apple identity token (JWT) |
| `authorization_code` | – | Apple auth code (optional, for revocation) |
| `email`, `name`, `provider_id`, `profile_image` | untrusted hints | untrusted hints (Apple sends name/email only on first sign-in) |
| `platform`, `guest_id` | `"mobile"`, guest id or null | same |

Verification:

- **Google** — verify the JWT signature against `https://www.googleapis.com/oauth2/v3/certs`
  (or use Google's PHP client `verifyIdToken`), and check
  `iss ∈ {accounts.google.com, https://accounts.google.com}`,
  `aud == 724842455682-9277p7oml8409inicouerru4ivl4ns0f.apps.googleusercontent.com` (the Web/server client),
  `exp` in the future, `email_verified == true`. Use `sub` as the stable user id.
- **Apple** — verify against `https://appleid.apple.com/auth/keys`, check
  `iss == https://appleid.apple.com`, `aud == com.jodealz.app`, `exp`. Use `sub`
  as the stable user id; the email may be a private relay address.

Response: unchanged — `{"status":"success","token":"<session token>"}`.

### 1.2 Account deletion — `POST /api/v1/auth/delete-account.php` (Critical)

Called from **Profile → Delete Account** after the user confirms.

- Headers: `Authorization: Bearer <token>`, `X-Auth-Token: <token>`
- Body: `{"confirm": true}`
- Must permanently delete the account and its personal data (profile, favorites,
  activity, device registrations, push tokens), invalidate all sessions, and for
  Apple users revoke the Apple token (`https://appleid.apple.com/auth/revoke`).
- Success: HTTP 200 `{"status":"success"}`. Anything else shows an error in the app.
- Data you must keep for legal reasons: keep it, and say so in the privacy policy.

Also publish a **public web page** (e.g. `https://jodealz.online/delete-account`)
that explains how to delete an account and lets signed-in users request it.
Google Play requires this URL in the Data safety form.

### 1.3 Notification preferences

The app now treats promotional ("marketing") pushes as **opt-in**. Set the
server-side default of `marketing_enabled` to `0` for new devices, and don't send
promotional pushes to devices that haven't opted in (App Store Guideline 4.5.4).

### 1.4 Device registration payload

`/api/register-device.php` now receives device model/OS/network/timezone **only
when the user opted in to usage data**; latitude/longitude are no longer sent.
Make sure the endpoint accepts payloads without those fields.

### 1.5 Push payloads

`data.url` in FCM messages must be a `https://jodealz.online/...` URL or a
relative path. Any other host is ignored and the app opens the home page.
Android notifications now use channel **`jodealz_notifications_v2`** (it has the
custom sound). If the server sets `android.notification.channel_id`, update it.

---

## 2. Files to host on jodealz.online

### 2.1 Android App Links — `https://jodealz.online/.well-known/assetlinks.json`

Serve as `application/json`, HTTPS, no redirects. Get both SHA-256 values from
Play Console → *Test and release → App integrity → App signing*.

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.jodealz.app",
      "sha256_cert_fingerprints": [
        "<PLAY APP SIGNING KEY SHA-256>",
        "<UPLOAD KEY SHA-256>"
      ]
    }
  }
]
```

Check on a device: `adb shell pm get-app-links com.jodealz.app` (should say `verified`).

### 2.2 iOS Universal Links — `https://jodealz.online/.well-known/apple-app-site-association`

No file extension, served as `application/json`, HTTPS, no redirects.
`TEAMID` is on developer.apple.com → Membership.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.jodealz.app"],
        "components": [
          { "/": "/admin/*", "exclude": true },
          { "/": "/*" }
        ]
      }
    ]
  }
}
```

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
2. In Xcode → Runner → Signing & Capabilities, choose your team (sets `DEVELOPMENT_TEAM`).
3. Sign in with Apple → Services ID/keys only if the website also offers Apple login.

### Google Play Console
1. Enroll in **Play App Signing**; keep the upload keystore + `android/key.properties` out of git.
2. If the developer account is a *personal* account created after 13 Nov 2023:
   run a **closed test with ≥ 12 testers for 14 consecutive days** before applying for production.

---

## 4. Build commands

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

> JoDeals is a deals app for Jordan. Native features beyond the website:
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
- [ ] §1.1 token verification and §1.2 deletion endpoint live and tested
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
