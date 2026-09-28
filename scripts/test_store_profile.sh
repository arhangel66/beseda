#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP" <<'PY'
import datetime, hashlib, pathlib, plistlib, sys
p = pathlib.Path(sys.argv[1]); cert = b'fixture certificate'
(p/'identity').write_text(hashlib.sha1(cert).hexdigest().upper())
profile = dict(TeamIdentifier=['TEAM'], Platform=['OSX'], ExpirationDate=datetime.datetime(2099,1,1), DeveloperCertificates=[cert], Entitlements={'application-identifier':'TEAM.app.beseda.Beseda'})
for name, change in [('good',{}), ('ios',{'Platform':['iOS']}), ('mixed-platform',{'Platform':['OSX','iOS']}), ('expired',{'ExpirationDate':datetime.datetime(2000,1,1)}), ('wrong-app',{'Entitlements':{'application-identifier':'TEAM.other'}}), ('wrong-team',{'TeamIdentifier':['OTHER']}), ('wrong-certificate',{'DeveloperCertificates':[b'other']})]:
    (p/name).write_bytes(plistlib.dumps(profile | change))
PY
identity="$(< "$TMP/identity")"
swift "$ROOT/scripts/validate_store_profile.swift" "$TMP/good" "$identity"
for case in ios mixed-platform expired wrong-app wrong-team wrong-certificate; do
    if swift "$ROOT/scripts/validate_store_profile.swift" "$TMP/$case" "$identity" >"$TMP/out" 2>&1; then
        echo "accepted $case" >&2; exit 1
    fi
done
mkdir "$TMP/bin"
printf '#!/bin/sh\ncat "$PROFILE_FIXTURE"\n' > "$TMP/bin/security"
chmod +x "$TMP/bin/security"
# The invalid profile must fail before build, signing or app copying.
for case in ios mixed-platform expired wrong-app wrong-team wrong-certificate; do
    if PROFILE_FIXTURE="$TMP/$case" PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/build_store_app.sh" "$TMP/missing-archive" "$identity" "$TMP/$case" >"$TMP/out" 2>&1; then
        echo "built with $case" >&2; exit 1
    fi
    grep -q 'invalid macOS provisioning profile' "$TMP/out"
done
echo 'store profile rejection stubs passed'
