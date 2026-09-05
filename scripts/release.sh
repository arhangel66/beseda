#!/usr/bin/env bash
# Publishes a release: release build, signed zip, appcast entry, GitHub release.
# Installed copies pick it up through Sparkle. Not the dev loop: nothing is killed
# or installed on this Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="arhangel66/beseda"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
TAG="v$VERSION"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

if gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1; then
    echo "$TAG is already published; bump VERSION first" >&2
    exit 1
fi
# a release must be reproducible from its tag
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "uncommitted changes; commit first" >&2
    exit 1
fi

swift build --package-path "$ROOT" -c release --product Beseda
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

# a fresh dir per release: generate_appcast describes every archive it finds, and one
# entry with the right download URL is all Sparkle needs
DIST="$ROOT/dist/$TAG"
rm -rf "$DIST"
mkdir -p "$DIST"
APP_DIR="$DIST/Beseda.app"
"$ROOT/scripts/lib/bundle_app.sh" "$BIN_DIR" "$APP_DIR" release

ZIP="$DIST/Beseda-$VERSION.zip"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"
rm -rf "$APP_DIR"

# signs the zip with the EdDSA key from the keychain; the feed lives at the repo root
# so its URL never changes
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    -o "$ROOT/appcast.xml" "$DIST"

git -C "$ROOT" add appcast.xml
git -C "$ROOT" commit -q -m "Beseda $VERSION"
git -C "$ROOT" tag -a "$TAG" -m "Beseda $VERSION"
git -C "$ROOT" push -q origin main "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Beseda $VERSION" --notes "Beseda $VERSION"

echo "published $TAG: https://github.com/$REPO/releases/tag/$TAG"
