# JO-Dealz — Codemagic CI/CD Deployment Guide

`codemagic.yaml` (repo root) defines three workflows:

| Workflow | Trigger | Machine | Output | Publishes to |
|---|---|---|---|---|
| `checks` | every push / PR | Linux | analyze + test report | — |
| `android-release` | git tag `v*` or manual | Linux | signed `.aab`, R8 mapping, Dart symbols | Google Play **internal** track (draft) |
| `ios-release` | git tag `v*` or manual | Mac mini M2 | signed `.ipa`, dSYMs, Dart symbols | App Store Connect → **TestFlight** |

Both release workflows run `flutter pub get`, `flutter analyze` and `flutter test`
before building. Release builds use `--obfuscate --split-debug-info`.

---

## 1. Project facts (verified)

| Item | Value | Where |
|---|---|---|
| Flutter / Dart | 3.44.6 (stable) / Dart ^3.10.7 | `codemagic.yaml` pins 3.44.6 |
| Android application ID | `com.jodealz.app` | `android/app/build.gradle.kts` |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 | `build.gradle.kts` (36 pinned; min from Flutter) |
| AGP / Kotlin / Gradle / Java | 8.11.1 / 2.2.20 / 8.14 / 17 | `settings.gradle.kts`, wrapper |
| iOS bundle ID | `com.jodealz.app` | Xcode project |
| iOS deployment target | 15.0 | Podfile + project |
| Apple Team ID | `9JA89QQL32` | Xcode project (`DEVELOPMENT_TEAM`) |
| Firebase project | `jodeals-eaec4` (number `724842455682`) | `google-services.json`, `lib/firebase_options.dart` |
| Backend | `https://jodealz.online` only (no localhost/staging) | `lib/services/trusted_hosts.dart` |
| Release logging | `debugPrint` silenced in release; Crashlytics off in debug | `lib/main.dart` |

### Versioning
- `pubspec.yaml`: `version: 2.0.21+27` → **version name** `2.0.21`, **build number** `27`.
- Android `versionCode` / iOS `CFBundleVersion` = the build number;
  `versionName` / `CFBundleShortVersionString` = the version name.
- Codemagic computes the build number: `max(latest on store, pubspec build) + 1`
  (Google Play via `google-play get-latest-build-number`, TestFlight via
  `app-store-connect get-latest-testflight-build-number`). The first upload uses the
  pubspec number. You only edit `pubspec.yaml` to change the **version name**.
- If a build with number ≥ 27 was already uploaded manually, the store lookup handles it.

---

## 2. Codemagic setup (one time)

1. **Add the app:** Codemagic → *Add application* → GitHub → `dirar318/jodealz-app`
   → project type *Flutter* → it detects `codemagic.yaml`.
2. **Android keystore:** *Team settings → Code signing identities → Android keystores →*
   upload `android/app/jodeals-release.jks` (alias `jodeals`) with its store and key
   passwords. **Reference name: `jodealz_upload_keystore`**.
3. **App Store Connect integration:** *Team settings → Integrations → Developer Portal →*
   add an App Store Connect API key named exactly **`JO-Dealz App Store Connect`**.
4. **iOS signing:** nothing to upload. `ios_signing` in the YAML fetches (or creates)
   the App Store distribution certificate and profile for `com.jodealz.app` through the
   integration. Optional: upload an existing distribution certificate (.p12) under
   *Code signing identities → iOS certificates* to reuse it.
5. **Environment variable groups** (*App settings → Environment variables*), all
   marked **Secret**:

| Group | Variable | Required | Value / where it comes from |
|---|---|---|---|
| `google_play` | `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | Yes (Android publish) | JSON key of a Google Cloud service account with access to the app in Play Console (*Users and permissions* → invite the service account email → "Release to testing tracks"). Created in Google Cloud Console → IAM → Service accounts → Keys → JSON. |
| `app_store` | `APP_STORE_APPLE_ID` | Recommended | Numeric **Apple ID** of the app: App Store Connect → the app → *App Information*. Not secret, but kept in a group so the YAML has no placeholder. |
| `firebase_optional` | `FIREBASE_SERVICE_ACCOUNT_JSON` | Optional | Firebase console → Project settings → Service accounts → *Generate new private key*. Used only to upload obfuscation symbols to Crashlytics. Leave the group empty to skip. |

Variables Codemagic creates automatically (don't add them):
`CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD`
(from the keystore reference) and the App Store Connect API credentials (from the
integration).

### What is intentionally *not* a secret
- `android/app/google-services.json` and `lib/firebase_options.dart` hold Firebase
  **client** identifiers (project/app IDs, a browser-style API key). Every copy of the
  app contains them, so they're not secrets. They're protected by API-key
  restrictions instead (§4.4). No Firebase admin/service-account key is in the repo.
- OAuth **client IDs** (Google, Apple bundle ID) are public identifiers. No OAuth
  **client secret** is used by the app.
- Keystore, `key.properties`, `.p8`/`.p12` files are git-ignored and must stay out of git.

---

## 3. Running builds

- **Android:** push a tag (`git tag v2.0.21 && git push origin v2.0.21`) or start
  `android-release` manually in Codemagic.
  - The bundle is checked to be **release-signed and not debug-signed**; the build
    fails otherwise.
  - Artifacts: `app-release.aab`, `mapping.txt`, `symbols/`.
- **iOS:** the same tag starts `ios-release`, or start it manually. Steps:
  `pod install` → `xcode-project use-profiles` → `flutter build ipa` with the
  generated `export_options.plist`. Artifacts: `.ipa`, dSYMs, Xcode logs.

### Deploying
- **Google Play:** Codemagic uploads to the **internal** track as a **draft**
  (`submit_as_draft: true`). **The very first `.aab` must be uploaded by hand** in
  Play Console (the API can't create the first release): download it from the
  Codemagic artifacts → Play Console → *Internal testing → Create release*. After the
  app is published once, set `submit_as_draft: false` and change `GOOGLE_PLAY_TRACK`
  as needed (`internal`, `alpha`, `beta`, `production`).
- **App Store Connect:** the IPA is uploaded and submitted to **TestFlight**. Submit for
  review in App Store Connect (or set `submit_to_app_store: true` once the listing,
  privacy answers and screenshots are ready). The app record for `com.jodealz.app`
  must exist in App Store Connect before the first upload (*My Apps → + New App*).

---

## 4. Firebase

The app uses **Firebase Core, Cloud Messaging and Crashlytics**. It does **not** use
Firebase Authentication: sign-in is handled by the JO-Dealz backend, which verifies
Google/Apple ID tokens itself (`public_html/includes/social-token-verifier.php`).

### 4.1 Android — OK
`google-services.json` matches `firebase_options.dart` (same app ID
`1:724842455682:android:a0a31f16bc27a3ffbfca9b` and key). Push and Crashlytics
(including R8 mapping upload) need no further setup.

### 4.2 iOS — ⚠️ must be regenerated before the first App Store build
The iOS values in `lib/firebase_options.dart` look hand-written (the file isn't from
the FlutterFire CLI):
- the iOS app ID suffix has 21 characters (`…:ios:cd5169a9414b2d18fca9b`), the Android
  one 22;
- iOS uses **the same API key** as Android, but Firebase normally creates a separate
  "iOS key".

If they're wrong, Firebase fails on iOS (no push token, no Crashlytics). Fix (needs
Firebase access):
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=jodeals-eaec4 --platforms=android,ios \
  --ios-bundle-id=com.jodealz.app --android-package-name=com.jodealz.app
```
Commit the regenerated `lib/firebase_options.dart`. Then update `FIREBASE_IOS_APP_ID`
in `codemagic.yaml` and the `-ai` value in the Xcode build phase
*Upload Crashlytics dSYMs* (`ios/Runner.xcodeproj/project.pbxproj`) if the iOS app ID
changed.

### 4.3 Push notifications (iOS)
Firebase console → Project settings → Cloud Messaging → *Apple app configuration* →
upload an **APNs Authentication Key (.p8)** (Apple Developer → Keys → + → Apple Push
Notifications service), with its Key ID and Team ID `9JA89QQL32`.

### 4.4 API key restrictions (Google Cloud Console → APIs & Services → Credentials)
- Android key → *Android apps* → package `com.jodealz.app` + the **SHA-1s** from §5.
- iOS key → *iOS apps* → bundle `com.jodealz.app`.

---

## 5. Google Sign-In

| Check | Status |
|---|---|
| Server (Web) client `724842455682-9277p7oml8409inicouerru4ivl4ns0f` | ✅ used by the app as `serverClientId` and accepted by the backend verifier |
| Android OAuth client for `com.jodealz.app` | ✅ exists in `google-services.json` with SHA-1 `34:5B:AF:AD:E5:04:7A:BE:EB:7E:FF:D7:93:EF:07:B0:7F:A2:74:1A` (not the debug key) |
| Play **App Signing** SHA-1 registered | ❓ Required: Play re-signs the app, so the Play signing key's SHA-1 must be registered too, or Google Sign-In fails for Play installs |
| iOS OAuth client | ❌ **missing in project `jodeals-eaec4`** |

### 5.1 Android SHA fingerprints
1. Play Console → *Test and release → App integrity → App signing*: copy the
   **App signing key** SHA-1 and SHA-256, plus the **Upload key** ones.
2. Firebase console → Project settings → Android app `com.jodealz.app` → *Add
   fingerprint*: add both SHA-1s (and SHA-256s). Download the new
   `google-services.json` and commit it.
3. Make sure `public_html/.well-known/assetlinks.json` lists the same two SHA-256s
   (for App Links).

Your upload key's fingerprints can be read locally with
`keytool -list -v -keystore android/app/jodeals-release.jks -alias jodeals`.

### 5.2 Create the iOS OAuth client (exact steps)
The app's `Info.plist` currently uses an iOS client from a **different Google Cloud
project** (`13492427447-4g9tvg970h18rliqe2v0dfu5ftbcq8q0`). The app won't crash, but
Google may refuse to issue an ID token for the `jodeals-eaec4` server client.
1. Google Cloud Console → select project **jodeals-eaec4** → *APIs & Services →
   Credentials → + Create credentials → OAuth client ID*.
2. Application type **iOS**; Name `JO-Dealz iOS`; Bundle ID **`com.jodealz.app`**;
   Team ID `9JA89QQL32`; App Store ID optional. Create.
3. Copy the **Client ID** (`724842455682-xxxx.apps.googleusercontent.com`) and the
   **iOS URL scheme** (`com.googleusercontent.apps.724842455682-xxxx`).
4. In `ios/Runner/Info.plist` replace `GIDClientID` with the new Client ID and the
   `CFBundleURLSchemes` entry with the new URL scheme. (Or run `flutterfire configure`,
   then copy the values from the generated `GoogleService-Info.plist`.)
5. Make sure the OAuth consent screen of `jodeals-eaec4` is **In production** (not
   *Testing*), or only listed test users can sign in.

---

## 6. Sign in with Apple

| Check | Status |
|---|---|
| Capability in the app (`Runner.entitlements`: `com.apple.developer.applesignin = Default`) | ✅ |
| Bundle ID `com.jodealz.app`, team `9JA89QQL32` | ✅ in the project |
| App ID capability enabled in Apple Developer | ❓ owner: Certificates, IDs & Profiles → Identifiers → `com.jodealz.app` → enable **Sign in with Apple**, **Push Notifications**, **Associated Domains**, then Save. Codemagic's profile then includes them; without this the iOS build fails at code signing. |
| Backend verifies the identity token (`aud = com.jodealz.app`) | ✅ `social-token-verifier.php` |
| Private key (.p8) | Not needed for native sign-in. **Needed only for token revocation** (below). |

### Account-deletion token revocation (Apple requirement)
When a user who signed in with Apple deletes their account, Apple asks apps to
revoke the user's tokens (`POST https://appleid.apple.com/auth/revoke`). This needs
server-side credentials the owner must create. They're **not** added as placeholders,
so nothing breaks:
1. Apple Developer → Keys → + → enable **Sign in with Apple** → configure with App ID
   `com.jodealz.app` → download the **.p8** (one download only) and note the **Key ID**.
2. Store on the **backend server** (not in the app or Codemagic): Team ID `9JA89QQL32`,
   Key ID, the .p8 contents, client ID `com.jodealz.app`.
3. Backend work (not yet implemented): at Apple sign-in, exchange the
   `authorization_code` the app already sends (`/auth/token`) and store the refresh
   token; in `delete-account.php` call `/auth/revoke` with it.
Until then, deletion still removes all data (the core App Store requirement).

---

## 7. Remaining manual steps (owner)

1. Regenerate the iOS Firebase config (§4.2) and upload the APNs key (§4.3).
2. Create the iOS OAuth client and update `Info.plist` (§5.2).
3. Register the Play App Signing + upload SHA-1/SHA-256 in Firebase and
   `assetlinks.json` (§5.1).
4. Enable the three capabilities on the App ID (§6).
5. Codemagic: add the app, keystore reference, App Store Connect integration and
   variable groups (§2).
6. Create the app records in Play Console and App Store Connect. Upload the first
   `.aab` to Play by hand (§3).
7. Deploy the backend changes in `D:\Projects\Personal\JoDeals` (see
   `docs/STORE_RELEASE.md` §1).
8. Optional: Apple token revocation (§6), `FIREBASE_SERVICE_ACCOUNT_JSON` for
   readable Dart stack traces.

---

## 8. Final checklist

Status as of this change. ✅ = done and verified; ⏳ = configured, verified only
once it runs on Codemagic; ❌ = blocked on the owner.

| Item | Status | Notes |
|---|---|---|
| Android build passes | ⏳ | `flutter analyze` and `flutter test` pass locally. The Gradle build couldn't run on the dev machine (environment socket error), so the first real build is on Codemagic. |
| Android `.aab` generated | ⏳ | `android-release` builds and collects it |
| Android signing configured | ✅ config / ⏳ run | Codemagic keystore → `CM_*` → Gradle. Unsigned or debug-signed bundles fail the build. |
| iOS build passes | ⏳ / ❌ | Needs a Mac (Codemagic), the App ID capabilities (§6) and the Firebase iOS config (§4.2) |
| iOS `.ipa` generated | ⏳ | `ios-release` builds and collects it |
| iOS signing configured | ✅ config / ❌ owner | Automatic via the integration; needs the integration + App ID capabilities |
| Firebase configured | ✅ Android / ❌ iOS | §4.2, §4.3 |
| Google Sign-In configured | ✅ Android (+ Play SHA-1 ❓) / ❌ iOS client | §5 |
| Apple Sign-In configured | ✅ app + backend / ❌ App ID capability | Revocation optional (§6) |
| Production API configured | ✅ | only `https://jodealz.online`; no dev URLs; release logs silenced |
| Codemagic workflow configured | ✅ | `codemagic.yaml` parsed and checked; build-number logic tested |
| Required secrets documented | ✅ | §2 |
| Remaining manual steps documented | ✅ | §7 |
