# SETUP.md — Signed & Notarized Builds for Ice Fire Fork

Linear checklist starting from the "Welcome to the Apple Developer Program" email. Follow top-to-bottom. Do not skip steps.

---

## 1. Verify enrollment

1. Go to https://developer.apple.com/account
2. Sign in with your Apple ID
3. Confirm the **Membership** section shows:
   - Entity: **Individual**
   - Status: **Active**
   - **Team ID**: a 10-character alphanumeric string (e.g. `A1B2C3D4E5`). Copy and save this — you'll need it as `APPLE_TEAM_ID`.

If you only see a "Membership pending" notice, Apple hasn't finished processing. Wait — usually <24h for individuals, sometimes instant.

---

## 2. Generate a Developer ID Application certificate

The cert type matters. Pick the wrong one and the whole pipeline silently produces unusable binaries.

### 2a. Create a Certificate Signing Request (CSR)

1. Open **Keychain Access** (`/System/Applications/Utilities/Keychain Access.app`)
2. Menu bar: **Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority…**
3. Fill in:
   - **User Email Address**: your Apple ID email (`p@durlej.me`)
   - **Common Name**: your full legal name (e.g. `Piotr Durlej`)
   - **CA Email Address**: leave blank
   - **Request is**: select **Saved to disk**
4. Click **Continue**, save as `CertificateSigningRequest.certSigningRequest` to your Desktop.

This action generates a private key in your login Keychain. **Do not delete it** — it pairs with the cert you'll download.

### 2b. Upload the CSR

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click the **+** (Create a Certificate) button
3. Under **Software**, select:
   - **Developer ID Application** — sign Mac apps and Developer ID Installer packages

   **NOT** `Apple Development` (only for development on your machine).
   **NOT** `Developer ID Installer` (for `.pkg` installers, not `.app`).
   **NOT** `Mac App Distribution` (for the Mac App Store, requires a different flow).

4. Click **Continue**
5. **Profile Type**: leave as **G2 Sub-CA (Xcode 11.4.1 or later)**
6. Upload your `CertificateSigningRequest.certSigningRequest` file
7. Click **Continue** → **Download**. You'll get a `developerID_application.cer` file.

### 2c. Import the cert into Keychain

1. Double-click `developerID_application.cer` in Finder
2. Keychain Access opens — confirm it imports into the **login** keychain (not System)
3. Click **Add**

---

## 3. Verify in Keychain Access

1. Open **Keychain Access**, select **login** keychain in the sidebar, **My Certificates** category
2. You should see: **Developer ID Application: Piotr Durlej (TEAMID)**
3. Click the disclosure triangle on the left — a private key labeled with your name must be nested under it.

If there's no disclosure triangle (no private key under the cert), the CSR was created on a different machine or the private key was deleted. Start over from step 2a on the machine where you'll export the .p12.

Sanity check from the terminal:

```bash
security find-identity -v -p codesigning
```

Expect a line like:

```
1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 "Developer ID Application: Piotr Durlej (TEAMID)"
```

---

## 4. Generate an app-specific password for notarytool

`notarytool` needs to authenticate against the Apple ID for notarization. **It will not accept your regular Apple ID password** — Apple requires an app-specific password for any non-interactive tool.

1. Go to https://appleid.apple.com
2. Sign in
3. Left sidebar: **Sign-In and Security**
4. Click **App-Specific Passwords** → **Generate an app-specific password** (the **+** button)
5. Label: `fire-fork-notarytool`
6. Click **Create**. You'll see a string like `abcd-efgh-ijkl-mnop`
7. **Copy it now.** Apple will not show it again. If you lose it you must revoke and regenerate.

Save this string — it goes into the `APP_SPECIFIC_PASSWORD` GitHub secret.

---

## 5. Export the cert + private key to a .p12

See `HELPER.md` for the exact commands. Result: a base64-encoded blob you'll paste into a GitHub secret.

---

## 6. Add secrets to GitHub Actions

Browser route: https://github.com/pdurlej/fire-from-ice/settings/secrets/actions → **New repository secret** for each of the six below. Or use the `gh secret set` shortcut in `HELPER.md`.

| Secret name | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded `.p12` (HELPER.md step 4) |
| `P12_PASSWORD` | Password you set on the `.p12` export |
| `APPLE_ID` | `p@durlej.me` (the Apple ID for your Dev Program account) |
| `APP_SPECIFIC_PASSWORD` | The app-specific password from step 4 |
| `APPLE_TEAM_ID` | The 10-char Team ID from step 1 |
| `KEYCHAIN_PASSWORD` | Any random string (run `uuidgen` to generate one). Used to lock the temporary keychain CI creates. |

Verify they all landed:

```bash
gh secret list --repo pdurlej/fire-from-ice
```

All six names should appear with recent timestamps.

---

## 7. Merge the signed-builds workflow into `fire/main`

The signing workflow lives on `feature/signed-builds-prep` (drafted separately). Merge it in:

```bash
cd /Users/pd/Developer/fire
git checkout fire/main
git pull origin fire/main
git merge --no-ff feature/signed-builds-prep -m "Merge signed-builds workflow"
git push origin fire/main
```

If conflicts surface in `.github/workflows/build-dmg.yml`, resolve in favor of the signed version (it supersedes the ad-hoc one).

---

## 8. Bump version in `Ice.xcodeproj/project.pbxproj`

Open `Ice.xcodeproj/project.pbxproj` in your editor and replace **both** occurrences (Debug + Release config):

```
MARKETING_VERSION = 0.11.13-fire.1;
CURRENT_PROJECT_VERSION = 1123;
```

with:

```
MARKETING_VERSION = 0.11.13-fire.2;
CURRENT_PROJECT_VERSION = 1124;
```

Commit:

```bash
git add Ice.xcodeproj/project.pbxproj
git commit -m "build: bump version to 0.11.13-fire.2 (build 1124)"
git push origin fire/main
```

---

## 9. Tag and push the release

```bash
git tag -a v0.11.13-fire.2 -m "first signed release"
git push origin v0.11.13-fire.2
```

The tag push is what triggers the release workflow.

---

## 10. Watch the CI run

Open https://github.com/pdurlej/fire-from-ice/actions and click into the running job. Expected steps in order:

1. **Setup Xcode** — pulls the Xcode version pinned in the workflow
2. **Import certificate** — decodes `BUILD_CERTIFICATE_BASE64`, imports into a temp keychain locked with `KEYCHAIN_PASSWORD`
3. **Archive (signed)** — `xcodebuild archive` with `CODE_SIGN_IDENTITY="Developer ID Application: Piotr Durlej (TEAMID)"`, hardened runtime, secure timestamp
4. **codesign --verify** — sanity check, must report `valid on disk` and `satisfies its Designated Requirement`
5. **notarytool submit** — uploads `.app` (or zipped `.app`) to Apple. **Waits 3–10 minutes** for Apple to process. If this step says `Status: Accepted`, you're good. If `Invalid`, see `TROUBLESHOOTING.md`.
6. **xcrun stapler staple** — attaches the notarization ticket to the `.app` so Gatekeeper can verify offline
7. **DMG repack** — wraps the stapled `.app` into a fresh DMG (the DMG itself isn't notarized, only the `.app` inside is — Gatekeeper checks the inner app on first launch)
8. **Upload to release artifact** — DMG attached to the GitHub Release for tag `v0.11.13-fire.2`

Total run time: ~15-25 minutes (most spent waiting on Apple's notary service).

---

## 11. Publish the appcast update

After CI is green:

```bash
/tmp/fire-publish-update.sh v0.11.13-fire.2
```

This signs the DMG with the existing Sparkle EdDSA key and appends an `<item>` to the appcast XML hosted at the fork's update URL. Sparkle signing is unchanged from prior releases — the new signed/notarized status is orthogonal to Sparkle's signature.

---

## 12. Verification on a clean machine

Download the DMG fresh from the GitHub Release (not your build directory — quarantine attribute matters), mount it, drag Ice.app to `/Applications`, then:

```bash
spctl -avv /Applications/Ice.app
```

Expected output:

```
/Applications/Ice.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Piotr Durlej (TEAMID)
```

- **`accepted`** + **`Notarized Developer ID`** = success.
- If `source=Developer ID` (no "Notarized" prefix), the staple step failed. Re-staple or re-run the workflow.
- If `rejected`, see TROUBLESHOOTING.md.

Then launch the app from Finder:

- **No Gatekeeper warning** ("X cannot be opened because the developer cannot be verified") — that dialog only appears for unsigned or revoked-cert apps.
- Open **Ice → Settings → Privacy permissions** — Accessibility, Screen Recording, etc. should **not** re-prompt. macOS TCC matches Developer ID Application authorizations on the certificate subject (your Team ID + Common Name), not on the binary's CDHash. So upgrades signed by the same cert preserve user grants across all future versions.

If TCC re-prompts on first launch after a signed upgrade, that's a real bug — see TROUBLESHOOTING.md.

---

## Reference

- Cert authority page: https://developer.apple.com/account/resources/certificates/list
- App-specific passwords: https://appleid.apple.com
- GitHub secrets UI: https://github.com/pdurlej/fire-from-ice/settings/secrets/actions
- Actions runs: https://github.com/pdurlej/fire-from-ice/actions
- Apple notarization status: https://developer.apple.com/system-status/ (check here if notarytool hangs >15 min)
