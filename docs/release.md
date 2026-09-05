# Releasing

1. Bump `VERSION`.
2. `./scripts/release.sh`.
3. Done: installed copies update themselves within about an hour (GitHub caches the
   feed for five minutes, Sparkle checks hourly and installs as soon as no call is
   being recorded). «Обновления» in the menu bar popover
   forces a check.

The script makes a release build, signs the zip with the EdDSA key from this Mac's
keychain, rewrites `appcast.xml` at the repo root, commits it, tags the commit
`v<version>`, pushes `main` with the tag and publishes the zip as a GitHub release in
`arhangel66/beseda`. It refuses to run when the tag already exists or the working tree
has uncommitted changes, so every release matches a commit.

The dev loop (`scripts/build_app.sh`, `scripts/package_app.sh`) never
carries the Sparkle keys, so a dev build does not update itself. Only a release build
does; the keys are written by `scripts/lib/bundle_app.sh` for the `release` flavour.

## The signing key

`generate_keys` created one EdDSA key pair; the private half sits in the login
keychain of Mikhail's Mac, the public half is in `bundle_app.sh`. Losing the private
key means no installed copy can ever be updated again, so keep a backup:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/beseda-sparkle-key.txt
```

Put that file into 1Password and delete it from the disk.

## Coming from Podushka

Podushka (up to 0.2.2) and Beseda are different apps for macOS: a Podushka copy never
updates into Beseda. Install `Beseda-0.3.0.zip` by hand once as described in
`install.md`, delete `Podushka.app`; the archive, settings and the downloaded model
move over on the first launch. Sparkle skips its scheduled check on the very first
launch of a bundle, so the first automatic update arrives after the second launch or
a manual check.
