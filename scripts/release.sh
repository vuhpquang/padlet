#!/usr/bin/env bash
# scripts/release.sh — cut a Padlet release end to end.
#
#   scripts/release.sh 2.0.1                    # notes generated from commits
#   scripts/release.sh 2.0.1 notes.md           # notes from a Markdown file
#   DRY_RUN=1 scripts/release.sh 2.0.1          # build + verify only, then undo the bump
#
# Steps: preflight → bump Info.plist → swift test → ./build.sh → verify the signer →
# update packaging/homebrew/padlet.rb → commit + tag + push develop → GitHub release with
# Padlet.dmg → regenerate Casks/padlet.rb in vuhpquang/homebrew-tap and push.
#
# Installed copies only accept updates signed by the same certificate, so the script
# refuses to publish anything not signed by RELEASE_CERT (the "Padlet Self-Signed" root).

set -euo pipefail
cd "$(dirname "$0")/.."

REPO="vuhpquang/padlet"
TAP_REPO="vuhpquang/homebrew-tap"
BRANCH="develop"
PLIST="Sources/Padlet/Resources/Info.plist"
CASK="packaging/homebrew/padlet.rb"
DMG="build/Padlet.dmg"
SIGN_IDENTITY="Padlet Self-Signed"
RELEASE_CERT="3e9ca590624d6067b7d52ad6e71756310b4d86a9"   # SHA-1 of that certificate
DRY_RUN="${DRY_RUN:-0}"

die()  { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

VERSION="${1:-}"
NOTES_FILE="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh X.Y.Z [notes.md]"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
TAG="v${VERSION}"

# ── Preflight ──────────────────────────────────────────────
step "Preflight"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || die "release from '$BRANCH'"
[[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
git fetch -q origin "$BRANCH" --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH")" ]] || die "$BRANCH is not in sync with origin"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
gh auth status >/dev/null 2>&1 || die "gh is not logged in"
security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\"" \
    || die "signing identity '$SIGN_IDENTITY' not in keychain (import ~/.config/padlet-signing/padlet-signing.p12)"

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
newest="$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
[[ "$VERSION" != "$CURRENT" && "$newest" == "$VERSION" ]] || die "$VERSION must be newer than $CURRENT"
echo "    $CURRENT (build $BUILD) → $VERSION (build $((BUILD + 1)))"

undo() {
    if [[ "$DRY_RUN" == "1" ]]; then git checkout -q -- "$PLIST" "$CASK"; fi
}
trap undo EXIT

# ── Bump, test, build ──────────────────────────────────────
step "Bumping $PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"

step "Running tests"
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
swift test >/dev/null 2>&1 || die "tests failed (run 'swift test')"

step "Building"
TEAM_ID="$SIGN_IDENTITY" ./build.sh

step "Verifying the release"
codesign --verify --deep --strict build/Padlet.app
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Padlet.app/Contents/Info.plist)"
[[ "$built" == "$VERSION" ]] || die "bundle says $built, expected $VERSION"
codesign -d -r- build/Padlet.app 2>&1 | grep -qi "certificate root = H\"$RELEASE_CERT\"" \
    || die "Padlet.app is not signed by the release certificate — installed copies would reject it"
[[ "$(lipo -archs build/Padlet.app/Contents/MacOS/Padlet)" == *arm64* ]] || die "missing arm64 slice"
[[ "$(lipo -archs build/Padlet.app/Contents/MacOS/Padlet)" == *x86_64* ]] || die "missing x86_64 slice"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "    signed by release certificate, universal, $DMG sha256 $SHA"

step "Updating $CASK"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
grep -E '^  (version|sha256) ' "$CASK"

if [[ "$DRY_RUN" == "1" ]]; then
    step "Dry run — stopping before commit; version bump reverted. Artifacts are in build/."
    exit 0
fi

# ── Publish ────────────────────────────────────────────────
step "Committing and tagging $TAG"
git add "$PLIST" "$CASK"
git commit -q -m "release: $TAG"
git tag -a "$TAG" -m "Padlet $VERSION"
git push -q origin "$BRANCH" "$TAG"

step "Creating GitHub release $TAG"
if [[ -n "$NOTES_FILE" ]]; then
    gh release create "$TAG" "$DMG" -R "$REPO" --title "Padlet $VERSION" --notes-file "$NOTES_FILE" --latest
else
    gh release create "$TAG" "$DMG" -R "$REPO" --title "Padlet $VERSION" --generate-notes --latest
fi

step "Updating Homebrew tap $TAP_REPO"
TAP_DIR="$(mktemp -d)"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q
{
    echo "# Generated from $CASK in $REPO — edit it there."
    sed -n '/^cask "padlet"/,$p' "$CASK"
} > "$TAP_DIR/Casks/padlet.rb"
git -C "$TAP_DIR" add Casks/padlet.rb
git -C "$TAP_DIR" commit -q -m "padlet $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"

step "Released Padlet $VERSION"
echo "    https://github.com/$REPO/releases/tag/$TAG"
echo "    brew upgrade --cask vuhpquang/tap/padlet"
