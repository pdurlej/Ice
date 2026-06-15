# HELPER.md — Export Cert + Private Key to GitHub Actions Secret

After step 3 of SETUP.md you have the Developer ID Application cert + private key sitting in your **login** keychain. This file gets it from there into a base64 blob suitable for `BUILD_CERTIFICATE_BASE64`.

Run all commands from a working directory you don't mind shredding afterward:

```bash
mkdir -p ~/fire-signing-tmp && cd ~/fire-signing-tmp
```

---

## 1. Confirm the cert is visible to codesign

```bash
security find-identity -v -p codesigning
```

A healthy entry looks like:

```
  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 "Developer ID Application: Piotr Durlej (TEAMID)"
     1 valid identities found
```

- The 40-char hex on the left is the cert SHA1 — you'd pass it to `codesign -s <hash>` if avoiding the CN string.
- The quoted string is the **Common Name (CN)**. The CI workflow will use this exact string (case-sensitive, including the space, colon, parens) as `CODE_SIGN_IDENTITY`.

If you see `0 valid identities found`, the cert is missing or has no associated private key. Go back to SETUP.md step 2.

---

## 2. Export to .p12 — GUI route (recommended)

The Keychain GUI handles the export ACLs correctly and is the path Apple actually supports.

1. Open **Keychain Access**
2. Select **login** keychain, **My Certificates** category
3. Locate **Developer ID Application: Piotr Durlej (TEAMID)**
4. Click the disclosure triangle — confirm a private key is nested under it
5. **Select the cert AND the private key together** (Cmd+click both rows). Exporting only the cert produces a useless .p12 with no key.
6. Right-click → **Export 2 items…**
7. **File Format**: **Personal Information Exchange (.p12)**
8. **Save As**: `cert.p12` in `~/fire-signing-tmp/`
9. Click **Save**
10. **Set a strong password** when prompted (this is `P12_PASSWORD`). Use something high-entropy — `openssl rand -base64 24` is a fine source. Save it to your password manager.
11. macOS will prompt for your **login keychain password** to authorize the export. Enter it.

Result: `~/fire-signing-tmp/cert.p12` (typically 3-5 KB).

---

## 3. Alternative: CLI export (less reliable)

Apple makes pure-CLI export difficult. The CLI only works if the cert was imported with permissive ACLs (which the default import does, but Apple updates have changed this in the past). If the GUI route worked, skip this section.

```bash
security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "<your-chosen-p12-password>" \
  -o cert.p12
```

If you get `SecKeychainItemExport: User interaction is not allowed.`, the private key's ACL forbids non-interactive export. Either:

- Use the GUI route above, or
- Open Keychain Access, right-click the private key → **Get Info** → **Access Control** tab → **Allow all applications to access this item**, then retry the CLI command.

---

## 4. Base64-encode for the GitHub secret

GitHub Actions secrets are plain text, so the binary `.p12` must be base64-encoded before pasting:

```bash
base64 -i cert.p12 -o cert.p12.b64
wc -c cert.p12.b64    # sanity check — should be a few KB
```

On macOS the default `base64` produces no line wrapping, which is what GitHub expects. If you use a Linux machine or a `base64` build with default wrapping, force no wrap:

```bash
base64 -w 0 cert.p12 > cert.p12.b64   # GNU coreutils
```

---

## 5. Upload all six secrets via `gh` (preferred)

If `gh` is authenticated (`gh auth status` shows you logged in), this is one shell block:

```bash
gh secret set BUILD_CERTIFICATE_BASE64 --repo pdurlej/fire-from-ice < cert.p12.b64
gh secret set P12_PASSWORD             --repo pdurlej/fire-from-ice --body "<the .p12 password you set in step 2>"
gh secret set APPLE_ID                 --repo pdurlej/fire-from-ice --body "p@durlej.me"
gh secret set APP_SPECIFIC_PASSWORD    --repo pdurlej/fire-from-ice --body "<app-specific password from SETUP step 4>"
gh secret set APPLE_TEAM_ID            --repo pdurlej/fire-from-ice --body "<10-char Team ID>"
gh secret set KEYCHAIN_PASSWORD        --repo pdurlej/fire-from-ice --body "$(uuidgen)"
```

Notes:
- `< cert.p12.b64` streams the file as the secret value — no leading/trailing whitespace, no editor mangling.
- `--body "<...>"` for the others avoids shell history. If you don't want them in `bash` history, prefix each line with a space (assuming `HISTCONTROL=ignorespace`) or run from a fresh `zsh -f` shell.
- `KEYCHAIN_PASSWORD` is throw-away — the CI workflow creates a temp keychain, locks it with this password, imports the cert, then nukes the keychain at the end of the run. Random UUID is fine; you never have to remember it.

---

## 6. Verify all six landed

```bash
gh secret list --repo pdurlej/fire-from-ice
```

Expect output like:

```
APPLE_ID                  Updated 2026-05-24
APPLE_TEAM_ID             Updated 2026-05-24
APP_SPECIFIC_PASSWORD     Updated 2026-05-24
BUILD_CERTIFICATE_BASE64  Updated 2026-05-24
KEYCHAIN_PASSWORD         Updated 2026-05-24
P12_PASSWORD              Updated 2026-05-24
```

All six must appear. Names are case-sensitive — the workflow references them by exact string.

---

## 7. Clean up local copies

The canonical copies now live in (a) your login keychain and (b) the GitHub secret store. The files in `~/fire-signing-tmp/` are now redundant attack surface — shred them:

```bash
cd ~/fire-signing-tmp
rm -P cert.p12 cert.p12.b64        # -P overwrites before unlink on macOS
cd ..
rmdir fire-signing-tmp
```

If you want belt-and-suspenders:

```bash
# Optional: overwrite the disk blocks of the directory itself
diskutil secureErase freespace 0 /
```

(That last one takes a while — only worth it on a multi-user machine or pre-disposal.)

---

## Recovery: if you lose the .p12

You don't need it. The same export procedure (steps 2-4 of this doc) regenerates it from the keychain. The `.p12` is a transient packaging format, not a unique secret.

What you **cannot lose**:
- The **private key in your login keychain** — back up the whole `~/Library/Keychains/login.keychain-db` to encrypted storage if paranoid.
- The **app-specific password** — Apple won't show it again. If you lose it, revoke at appleid.apple.com and generate a new one, then update the `APP_SPECIFIC_PASSWORD` secret.

If the keychain is wiped (machine loss, disk failure with no backup), you'd need to:
1. Generate a new CSR on the replacement machine
2. **Revoke the old Developer ID Application cert** at developer.apple.com (you only get a small number of active certs per Team)
3. Issue a new cert against the new CSR
4. Re-export and update `BUILD_CERTIFICATE_BASE64` + `P12_PASSWORD`

Users of existing signed builds are unaffected — the old cert remains valid for signature verification of already-distributed binaries; revocation only stops you from signing new ones with it.
