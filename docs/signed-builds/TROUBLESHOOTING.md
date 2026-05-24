# TROUBLESHOOTING.md — First Signed/Notarized Build Failures

Errors you're likely to hit on the first run of the signed-builds workflow, what they actually mean, and the fix. Listed roughly in the order they'd appear during a CI run (cert import → archive → notarize → staple → distribute).

---

## Certificate import

### `security: SecKeychainItemImport: MAC verification failed during PKCS12 import. (Wrong password?)` / `errSecAuthFailed`

**When**: `security import cert.p12 -k ...` step in the workflow.
**Cause**: `P12_PASSWORD` secret doesn't match the password you set when exporting the `.p12` from Keychain Access.
**Fix**:
1. Re-export the `.p12` (HELPER.md step 2) with a known password — type it carefully, no copy-paste artifacts.
2. Update both `BUILD_CERTIFICATE_BASE64` (the new export's base64) and `P12_PASSWORD` together. They're paired.
3. Common gotcha: trailing newline in the secret. `gh secret set --body "..."` is safe; pasting into the browser UI sometimes appends a newline. Re-set via `gh` if unsure.

### `security: SecKeychainItemImport: One or more parameters passed to a function were not valid.`

**Cause**: `BUILD_CERTIFICATE_BASE64` isn't valid base64, usually due to line wrapping or extra whitespace.
**Fix**: Re-encode with `base64 -i cert.p12 -o cert.p12.b64` (no `-b` flag) on macOS, or `base64 -w 0` on Linux. Re-upload.

---

## Archive / codesign

### `Code signing error: No signing certificate "Developer ID Application" found` / `no signing identity found`

**When**: `xcodebuild archive` step.
**Causes** (in likelihood order):
1. The cert imported but the **private key did not** — the `.p12` was exported with only the cert selected, not the cert + key pair. Verify locally: `security find-identity -v -p codesigning` on your machine should list it; if it does, the export step lost the key.
2. The `CODE_SIGN_IDENTITY` string in the workflow / project file doesn't match the cert's Common Name **exactly**. Case-sensitive, includes the colon, space, parens, and Team ID:
   ```
   Developer ID Application: Piotr Durlej (TEAMID)
   ```
   Compare against `security find-identity -v -p codesigning` output character-by-character.
3. The temp keychain isn't on the search list. The workflow must run `security list-keychains -s build.keychain $(security list-keychains -d user | tr -d '"')` to add the temp keychain *to* the search list (not replace it).

**Fix**: Re-export with cert + key selected (Cmd+click both rows in Keychain Access). Confirm exact CN string. Inspect workflow's keychain setup steps.

### `errSecInternalComponent` during codesign

**Cause**: The keychain holding the private key is locked. CI builds need an explicit unlock step after import.
**Fix**: Workflow must run `security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain` before `xcodebuild`. Also: `security set-keychain-settings -lut 21600 build.keychain` to keep it unlocked for the whole run.

### `The executable does not have the hardened runtime enabled.`

**When**: codesign step or notarytool rejection.
**Cause**: Notarization **requires** the hardened runtime. Missing means Apple's notary service rejects the submission.
**Fix**: One of:
- Add `--options runtime` to the `codesign` invocation, OR
- Set `ENABLE_HARDENED_RUNTIME = YES` in the project's build settings for the Release configuration, OR
- Pass `OTHER_CODE_SIGN_FLAGS="--options=runtime"` to `xcodebuild`.

### `The signature does not include a secure timestamp.`

**Cause**: `codesign` didn't contact Apple's timestamp server. Notarization requires a secure timestamp on every signed binary.
**Fix**:
- Add `--timestamp` to the `codesign` invocation, OR set in project: `OTHER_CODE_SIGN_FLAGS="--timestamp"`.
- The build machine needs **network access** to `https://timestamp.apple.com` during signing. GitHub-hosted runners do; self-hosted runners behind a firewall may not. If you ever see `Warning: unable to build chain to self-signed root for signer "..."` or `timestamps service is not available`, it's a network issue.

### `code object is not signed at all` for a bundled framework

**Cause**: Xcode signs the outer `.app` but not deeply enough — some nested binary (Sparkle.framework, an embedded XPC service, a Helper.app) isn't signed.
**Fix**: Use `--deep` on the outer codesign call, OR (preferred) sign each nested binary explicitly bottom-up before signing the wrapper. The Ice project already pulls in Sparkle and any helpers; the signed-builds workflow's archive step should use `CODE_SIGN_STYLE=Manual` and rely on Xcode's resource-aware signing.

---

## Notarization

### `Error: HTTP status code: 401. Authentication failed for Apple ID "..."` / `Error: 1064: Authentication failed`

**When**: `xcrun notarytool submit ...` step.
**Causes**:
1. `APP_SPECIFIC_PASSWORD` secret holds your **regular Apple ID password** — Apple rejects these for notarytool. Must be an app-specific password from appleid.apple.com.
2. The app-specific password has been revoked (you have 25 max; old ones get rotated).
3. `APPLE_ID` doesn't match the Apple ID that owns the Developer Program account.

**Fix**: Generate a fresh app-specific password (SETUP.md step 4), update `APP_SPECIFIC_PASSWORD`. Verify `APPLE_ID` is `p@durlej.me` (or whatever email is on your developer.apple.com account).

### `Error: 1133: Invalid team-id "..."`

**Cause**: `APPLE_TEAM_ID` is malformed (must be exactly 10 alphanumeric chars) or doesn't match the team that owns the signing cert.
**Fix**: Recopy from https://developer.apple.com/account → Membership. No quotes, no spaces, no `Team `. Just the 10 chars.

### Notarization completes but `Status: Invalid`

**When**: notarytool finishes the upload but Apple's evaluation rejects the submission.
**Diagnosis**: Pull the detailed log:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"
```

The `<submission-id>` is in the workflow output from the `notarytool submit` step (a UUID).

Common rejections in the log:
- **"The binary is not signed with a valid Developer ID certificate"** — wrong cert type, or unsigned nested binary. Re-check signing.
- **"The signature does not include a secure timestamp"** — see codesign section above.
- **"The executable does not have the hardened runtime enabled"** — see codesign section above.
- **"The binary uses an SDK older than the 10.9 SDK"** — unlikely for Ice (macOS 14+), but flagged when build settings target ancient SDKs.
- **"The signature of the binary is invalid"** — re-sign was botched; rebuild from clean.
- **`com.apple.security.cs.disable-library-validation` entitlement on a non-bundled binary** — entitlements file lists an entitlement the bundle isn't allowed to claim.

### Notarytool hangs >15 minutes

**Cause**: Apple's notary service is degraded.
**Fix**: Check https://developer.apple.com/system-status/. The service shows up there. If degraded, wait — restarting the workflow won't help and burns minutes.

---

## Stapling & DMG packaging

### `Could not staple ticket to "Ice.app"` / `CloudKit query for ... unsuccessful`

**Cause**: Notarization didn't actually succeed, or the workflow ran `stapler` before Apple's CDN propagated the ticket (rare, but happens within seconds of notarytool returning).
**Fix**:
1. Verify the prior notarytool step reported `Status: Accepted`, not just success of the HTTP call.
2. Add a small retry / sleep before stapling — usually 10-30s is enough.
3. Confirm online: `xcrun stapler staple -v Ice.app`. The `-v` flag prints the CloudKit query Apple is making.

### Stapled the DMG instead of the .app

**Symptom**: `spctl -avv /Volumes/.../Ice.app` shows `source=Developer ID` (not `Notarized Developer ID`) even though notarytool said Accepted.
**Cause**: Apple's notarization metadata can attach to either the `.app` or the `.dmg`, but for distribution where the user drags the app out of the DMG and runs it from `/Applications`, the **ticket must be on the `.app`** so it travels with the binary.
**Fix**: Order matters in the workflow:
1. `xcrun notarytool submit Ice.app.zip` (zipped because notarytool wants a single file)
2. **Unzip** the original `Ice.app` if it was zipped destructively
3. `xcrun stapler staple Ice.app` — staples onto the `.app`
4. **Now** package the stapled `.app` into the DMG
5. Optionally also `xcrun stapler staple Ice.dmg` for the DMG itself

Don't repack the DMG **after** stapling only the inner .app and **before** stapling — order is staple-then-repack.

---

## Post-distribution checks

### `spctl -avv /Applications/Ice.app` says `rejected`

**Possible outputs and meanings**:
- `rejected\nsource=Unnotarized Developer ID` → signed but not notarized. Notarytool succeeded only if you also stapled. Restart from notarize/staple.
- `rejected\nsource=no usable signature` → signature corrupted in transit. Re-download fresh from the GitHub Release page, not from a build artifact.
- `rejected (the code is valid but does not seem to be an app)` → spctl was pointed at a binary inside the bundle, not the bundle root. Always: `spctl -avv /Applications/Ice.app` not `spctl -avv /Applications/Ice.app/Contents/MacOS/Ice`.

### First launch still shows Gatekeeper "cannot be opened because the developer cannot be verified"

**For a properly Developer-ID-signed and notarized build, this dialog should never appear.** If it does:
1. The download path stripped or corrupted the notarization. Check `xattr /Applications/Ice.app` — `com.apple.quarantine` will be set on any downloaded file, that's normal. But the staple should make Gatekeeper accept it on first launch.
2. Run `spctl -avv` first. If that says `accepted` but the dialog appears, the user has hardened Gatekeeper settings ("App Store only" in System Settings → Privacy & Security). Tell them to set it to "App Store and identified developers".
3. If `spctl` says `rejected` despite the workflow reporting success, the binary in the DMG isn't the one that got stapled — packaging order bug (see "Stapled the DMG instead of the .app" above).

### TCC re-prompts for Accessibility / Screen Recording after upgrade

**Should not happen** with Developer ID. macOS TCC matches authorizations to the certificate's subject (Team ID + Common Name), and so long as the new build is signed by the same Developer ID Application cert, TCC carries grants forward.

**If it does happen**, diagnose:

```bash
codesign -dv --verbose=4 /Applications/Ice.app 2>&1 | grep -i 'TeamIdentifier\|Authority'
```

Compare against the previous version that worked. If `TeamIdentifier` differs, you've signed with a different cert (perhaps the "Apple Development" cert instead of "Developer ID Application", or a different Team). If `Authority` (the certificate chain) differs, you may have regenerated the cert under a different Apple ID.

If TCC re-prompts despite identical `TeamIdentifier`, it's a real macOS bug; user can re-grant once and it'll persist for subsequent versions.

### `spctl` works locally but users report Gatekeeper rejection

Quarantine state can differ between your machine (where the file was built or moved through trusted paths) and a user's machine (downloaded from GitHub Releases via browser, marking `com.apple.quarantine`). To replicate the user experience locally:

```bash
xattr -w com.apple.quarantine "0083;$(printf '%x' $(date +%s));Safari;ABCDEF" /tmp/Ice.dmg
hdiutil attach /tmp/Ice.dmg
spctl -avv "/Volumes/Ice/Ice.app"
```

If that passes, real users will too.

---

## General debugging tips

- Pull the **full** notarytool log every time — Apple's submit step output is terse, the log is verbose.
- `codesign -dv --verbose=4 Ice.app` shows the full signature, entitlements, and team identifier. Run it on both the local build and the CI-produced build for diffs.
- `codesign --verify --deep --strict --verbose=2 Ice.app` is the same check Gatekeeper runs at install time. If this fails, Gatekeeper will fail.
- The GitHub Actions runner has Xcode pre-installed but the version drifts. Pin the Xcode version with `sudo xcode-select -s /Applications/Xcode_15.4.app` in the workflow if Apple breaks things between SDK releases.
- If completely stuck, run the same `xcodebuild` + `codesign` + `notarytool` sequence locally on your Mac with the cert in your login keychain. CI is just doing what you'd do — local repro is faster than 20-minute CI cycles.
