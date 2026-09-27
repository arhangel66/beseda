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
# a release must be reproducible from its tag
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "uncommitted changes; commit first" >&2
    exit 1
fi
if [ ! -f "$NOTES" ]; then
    echo "no $NOTES; an update has to say what changed" >&2
    exit 1
fi

# Every step below checks what an earlier run left behind, so after any failure the
# fix is to rerun. The feed changes last: until then no installed copy sees anything.
FEED_URL="https://github.com/$REPO/releases/download/$TAG/Beseda-$VERSION.zip"

# the feed commit is the last step; pushing it is all a rerun has left to do
if grep -qF "$FEED_URL" "$ROOT/appcast.xml"; then
    git -C "$ROOT" push -q origin main
    echo "published $TAG: https://github.com/$REPO/releases/tag/$TAG"
    exit 0
fi

# the tag is reused only where it marks this very commit
HEAD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
git -C "$ROOT" fetch -q origin "refs/tags/$TAG:refs/tags/$TAG" 2> /dev/null || true
if TAG_COMMIT="$(git -C "$ROOT" rev-parse -q --verify "$TAG^{commit}")"; then
    if [ "$TAG_COMMIT" != "$HEAD_COMMIT" ]; then
        echo "$TAG points at $TAG_COMMIT, not HEAD $HEAD_COMMIT; bump VERSION or delete the tag" >&2
        exit 1
    fi
else
    git -C "$ROOT" tag -a "$TAG" -m "Beseda $VERSION"
fi
git -C "$ROOT" push -q origin "$TAG"

DIST="$ROOT/dist/$TAG"
IS_DRAFT="$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft 2> /dev/null || echo missing)"
HAS_ASSET="$(gh release view "$TAG" --repo "$REPO" --json assets \
    --jq "any(.assets[]; .name == \"Beseda-$VERSION.zip\")" 2> /dev/null || echo false)"

# a build is needed only while GitHub has no zip: a rebuilt zip differs from the uploaded one
if [ "$HAS_ASSET" != "true" ]; then
    swift test --jobs 2 --package-path "$ROOT"
    swift build --package-path "$ROOT" -c release --product Beseda
    BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
    rm -rf "$DIST"
    mkdir -p "$DIST"
    APP_DIR="$DIST/Beseda.app"
    "$ROOT/scripts/lib/bundle_app.sh" "$BIN_DIR" "$APP_DIR" release
    ditto -c -k --keepParent "$APP_DIR" "$DIST/Beseda-$VERSION.zip"
    rm -rf "$APP_DIR"
    if [ "$IS_DRAFT" = "missing" ]; then
        gh release create "$TAG" --repo "$REPO" --draft --verify-tag \
            --title "Beseda $VERSION" --notes-file "$NOTES"
        IS_DRAFT="true"
    fi
    gh release upload "$TAG" "$DIST/Beseda-$VERSION.zip" --repo "$REPO" --clobber
fi

# the feed is signed from the bytes GitHub holds, not from a local copy. A fresh dir:
# generate_appcast describes every archive it finds, and pairs notes with one by filename
FEED_DIR="$DIST/feed"
rm -rf "$FEED_DIR"
mkdir -p "$FEED_DIR"
gh release download "$TAG" --repo "$REPO" --pattern "Beseda-$VERSION.zip" --dir "$FEED_DIR"
cp "$NOTES" "$FEED_DIR/Beseda-$VERSION.md"
# signs with the EdDSA key from the keychain; --embed-release-notes leaves nothing extra to host
cp "$ROOT/appcast.xml" "$DIST/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes \
    -o "$DIST/appcast.xml" "$FEED_DIR"
SIGNATURE="$(grep -F "$FEED_URL" "$DIST/appcast.xml" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
if [ -z "$SIGNATURE" ]; then
    echo "no signed entry for $FEED_URL in $DIST/appcast.xml" >&2
    exit 1
fi

# a draft's download URL is not public, so the public check can only follow publishing;
# the feed is still untouched if it fails
if [ "$IS_DRAFT" = "true" ]; then
    gh release edit "$TAG" --repo "$REPO" --draft=false
fi
curl -fsSL -o "$DIST/public.zip" "$FEED_URL"
cmp "$FEED_DIR/Beseda-$VERSION.zip" "$DIST/public.zip"
"$SPARKLE_BIN/sign_update" --verify "$DIST/public.zip" "$SIGNATURE"

cp "$DIST/appcast.xml" "$ROOT/appcast.xml"
git -C "$ROOT" add appcast.xml
git -C "$ROOT" commit -q -m "Beseda $VERSION"
git -C "$ROOT" push -q origin main

echo "published $TAG: https://github.com/$REPO/releases/tag/$TAG"
