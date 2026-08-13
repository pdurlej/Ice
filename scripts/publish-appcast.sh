#!/usr/bin/env bash
#
# publish-appcast.sh — automate the Sparkle appcast publish for a fire release.
#
# Replaces the hand-run ritual (issue #10): download the release DMG, EdDSA-sign
# it, insert a new <item> into pdurlej/fire-releases/appcast.xml, push it, and
# wait for GitHub Pages to serve it.
#
# The Sparkle private key STAYS in the owner's Keychain — signing happens
# LOCALLY (one Keychain "Allow" prompt), never in CI. Run this after the tag's
# CI build has published the GitHub release.
#
# Usage:
#   scripts/publish-appcast.sh v0.11.13-fire.10.6 [--notes-file notes.html] [--dry-run]
#
# The tag must be v<shortVersion> (e.g. v0.11.13-fire.10.6). Idempotent: an
# existing version is accepted only after its build, URL, length, and EdDSA
# signature are verified against the published DMG.

set -euo pipefail

REPO="pdurlej/fire-from-ice"
RELEASES_REPO="pdurlej/fire-releases"
PAGES_URL="https://pdurlej.github.io/fire-releases/appcast.xml"
MIN_SYSTEM_VERSION="14.0"
GIT_NAME="Piotr Durlej"
GIT_EMAIL="pdurlej@users.noreply.github.com"

TAG=""
NOTES_FILE=""
DRY_RUN=0

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    v*) TAG="$1"; shift ;;
    *) die "unknown argument: $1 (expected a tag like v0.11.13-fire.10.6)" ;;
  esac
done

[ -n "$TAG" ] || die "no tag given. Usage: $0 v0.11.13-fire.X [--notes-file f] [--dry-run]"
[ -z "$NOTES_FILE" ] || [ -f "$NOTES_FILE" ] || die "notes file not found: $NOTES_FILE"
command -v gh >/dev/null || die "gh CLI not found"

# Tag → short version (the ship flow always tags v<shortVersion>).
SHORT_VERSION="${TAG#v}"

MOUNT=""
WORK="$(mktemp -d)"
cleanup() { [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

# --- 1. Clone the releases repo + idempotency check (before any side effect) --
info "Cloning $RELEASES_REPO"
git clone -q "https://github.com/$RELEASES_REPO.git" "$WORK/releases"
APPCAST="$WORK/releases/appcast.xml"
[ -f "$APPCAST" ] || die "appcast.xml not found in $RELEASES_REPO"
ALREADY_PRESENT=0
if grep -q "<sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>" "$APPCAST"; then
  ALREADY_PRESENT=1
fi

# --- 2. Download the release DMG ---------------------------------------------
info "Downloading $TAG DMG from $REPO"
gh release download "$TAG" -R "$REPO" -D "$WORK" --pattern '*.dmg' \
  || die "could not download the DMG for $TAG (has the CI release published yet?)"
DMG="$(ls "$WORK"/*.dmg 2>/dev/null | head -1)"
[ -n "$DMG" ] || die "no .dmg in the downloaded release"
LENGTH="$(stat -f '%z' "$DMG")"
DMG_NAME="$(basename "$DMG")"
ENCLOSURE_URL="https://github.com/$REPO/releases/download/$TAG/$DMG_NAME"

# --- 3. Read + sanity-check the version from the DMG's Info.plist -------------
# `-plist` + plistlib, NOT text parsing: with `-quiet` hdiutil prints nothing,
# and the volume name contains spaces ("Ice v0.11.13-…"), so grepping the text
# table truncates the path. (Both bit the first live run of this script.)
MOUNT="$(hdiutil attach "$DMG" -nobrowse -plist | python3 -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
print(next(e["mount-point"] for e in d["system-entities"] if "mount-point" in e))
')"
[ -n "$MOUNT" ] || die "failed to mount $DMG_NAME"
APP="$(ls -d "$MOUNT"/*.app 2>/dev/null | head -1)"
[ -n "$APP" ] || die "no .app inside the DMG"
DMG_SHORT="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
BUILD_VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
hdiutil detach "$MOUNT" -quiet; MOUNT=""
[ "$DMG_SHORT" = "$SHORT_VERSION" ] \
  || die "tag says $SHORT_VERSION but the DMG is $DMG_SHORT — tag/build mismatch, aborting"
info "version=$SHORT_VERSION build=$BUILD_VERSION length=$LENGTH"

# --- 4. Sign the DMG (Keychain prompt) ---------------------------------------
info "Signing the DMG (a Keychain 'Allow' prompt may appear)"
SIGN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*artifacts/sparkle/Sparkle/bin/sign_update' 2>/dev/null | head -1)"
[ -n "$SIGN" ] || SIGN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*checkouts/Sparkle/sign_update' 2>/dev/null | head -1)"
[ -n "$SIGN" ] || die "sign_update not found — build the app once so SPM resolves Sparkle"
SIGN_OUT="$("$SIGN" "$DMG")"   # sparkle:edSignature="..." length="..."
ED_SIGNATURE="$(echo "$SIGN_OUT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIGNATURE" ] || die "sign_update produced no signature (output: $SIGN_OUT)"

if [ "$ALREADY_PRESENT" = "1" ]; then
  python3 "$ROOT/scripts/verify_appcast_entry.py" \
    "$APPCAST" "$SHORT_VERSION" "$BUILD_VERSION" "$ED_SIGNATURE" \
    "$LENGTH" "$ENCLOSURE_URL"
  info "appcast already has $SHORT_VERSION and exactly matches the published DMG."
  exit 0
fi

# --- 5. Build + insert the <item>, validate well-formedness ------------------
PUBDATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
if [ -n "$NOTES_FILE" ]; then
  DESCRIPTION_HTML="$(cat "$NOTES_FILE")"
else
  DESCRIPTION_HTML="<p>See the <a href=\"https://github.com/$REPO/releases/tag/$TAG\">full release notes on GitHub</a>.</p>"
fi
python3 - "$APPCAST" "$SHORT_VERSION" "$BUILD_VERSION" "$PUBDATE" "$ED_SIGNATURE" \
         "$LENGTH" "$ENCLOSURE_URL" "$MIN_SYSTEM_VERSION" "$DESCRIPTION_HTML" <<'PY'
import sys, xml.dom.minidom as minidom
appcast, short_v, build_v, pubdate, sig, length, url, min_sys, desc = sys.argv[1:10]
item = f'''            <item>
            <title>{short_v}</title>
            <pubDate>{pubdate}</pubDate>
            <sparkle:version>{build_v}</sparkle:version>
            <sparkle:shortVersionString>{short_v}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{min_sys}</sparkle:minimumSystemVersion>
            <description><![CDATA[
                {desc}
            ]]></description>
            <enclosure
                url="{url}"
                sparkle:edSignature="{sig}"
                length="{length}"
                type="application/octet-stream" />
        </item>
'''
with open(appcast) as f:
    content = f.read()
if content.count('</channel>') != 1:
    sys.exit("appcast.xml has an unexpected number of </channel> tags")
content = content.replace('    </channel>', item + '    </channel>', 1)
with open(appcast, 'w') as f:
    f.write(content)
minidom.parse(appcast)   # raises if not well-formed
print("inserted + validated")
PY

if [ "$DRY_RUN" = "1" ]; then
  info "DRY RUN — generated diff (nothing pushed):"
  echo "------------------------------------------------------------"
  git -C "$WORK/releases" --no-pager diff
  echo "------------------------------------------------------------"
  exit 0
fi

# --- 6. Commit + push --------------------------------------------------------
info "Committing + pushing to $RELEASES_REPO"
git -C "$WORK/releases" add appcast.xml
git -C "$WORK/releases" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" \
  commit -q -m "appcast: $SHORT_VERSION (build $BUILD_VERSION)"
git -C "$WORK/releases" push -q origin HEAD

# --- 7. Wait for GitHub Pages to propagate -----------------------------------
info "Waiting for GitHub Pages to propagate"
for i in $(seq 1 20); do
  if curl -fsS "$PAGES_URL" 2>/dev/null | grep -q "<sparkle:shortVersionString>$SHORT_VERSION<"; then
    info "LIVE on Pages: $SHORT_VERSION (after ~$((i*8))s)"
    exit 0
  fi
  sleep 8
done
info "pushed, but $SHORT_VERSION not visible on Pages after 160s — the raw repo is correct; Pages CDN may still be caching."
