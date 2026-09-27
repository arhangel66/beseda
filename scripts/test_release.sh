#!/usr/bin/env bash
# Exercises the step-6 rerun without network, signing, building, or changing this checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/scripts/release.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/scripts" "$TMP/repo/dist/v0.0.0" "$TMP/bin"
cp "$ROOT/scripts/release.sh" "$TMP/repo/scripts/release.sh"
printf '0.0.0\n' > "$TMP/repo/VERSION"
printf '<feed/>\n' > "$TMP/repo/appcast.xml"
cp "$TMP/repo/appcast.xml" "$TMP/repo/dist/v0.0.0/appcast.xml"

cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"rev-parse --abbrev-ref HEAD"* ]]; then
    echo main
elif [[ "$*" == *":!appcast.xml"* ]]; then
    exit 0
elif [[ "$*" == *"status --porcelain"* ]]; then
    echo ' M appcast.xml'
fi
STUB
chmod +x "$TMP/bin/git"

output="$(PATH="$TMP/bin:$PATH" "$TMP/repo/scripts/release.sh")"
expected='published v0.0.0: https://github.com/arhangel66/beseda/releases/tag/v0.0.0'
[ "$output" = "$expected" ] || {
    printf 'unexpected release output:\n%s\n' "$output" >&2
    exit 1
}
