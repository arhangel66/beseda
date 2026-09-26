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
NOTES="$ROOT/docs/release-notes/$VERSION.md"

# the feed Sparkle reads lives on main, and the commit below lands on the current
# branch: a release cut anywhere else publishes a tag and a zip while leaving every
# installed copy on the old version, without a single command failing
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
    echo "on $BRANCH; releases are cut from main" >&2
    exit 1
fi
if gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1; then
    echo "$TAG is already published; bump VERSION first" >&2
    exit 1
fi
# a release must be reproducible from its tag
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "uncommitted changes; commit first" >&2
    exit 1
fi
if [ ! -f "$NOTES" ]; then
    echo "no $NOTES; an update has to say what changed" >&2
    exit 1
fi

swift test --jobs 2 --package-path "$ROOT"
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

# generate_appcast pairs release notes with an archive by filename
cp "$NOTES" "$DIST/Beseda-$VERSION.md"

# signs the zip with the EdDSA key from the keychain; the feed lives at the repo root
# so its URL never changes. --embed-release-notes puts the notes inside the feed,
# leaving nothing extra to host. Written into dist first: the repo's feed changes only
# once the zip it points at is downloadable
cp "$ROOT/appcast.xml" "$DIST/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes \
    -o "$DIST/appcast.xml" "$DIST"

# the zip goes up first, on a tag at the last pushed commit; a failed upload stops here
# with main and the feed untouched. A rerun after a failure needs the tag deleted
# (git push origin :$TAG && git tag -d $TAG)
git -C "$ROOT" tag -a "$TAG" -m "Beseda $VERSION"
git -C "$ROOT" push -q origin "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --verify-tag --title "Beseda $VERSION" --notes-file "$NOTES"
curl -fsSL -o "$DIST/downloaded.zip" "https://github.com/$REPO/releases/download/$TAG/Beseda-$VERSION.zip"
cmp "$ZIP" "$DIST/downloaded.zip"

cp "$DIST/appcast.xml" "$ROOT/appcast.xml"
git -C "$ROOT" add appcast.xml
git -C "$ROOT" commit -q -m "Beseda $VERSION"
git -C "$ROOT" push -q origin main

echo "published $TAG: https://github.com/$REPO/releases/tag/$TAG"
