# Releasing

1. Bump `VERSION`.
2. Write `docs/release-notes/<version>.md`: what changed, for the person who sees the
   update dialog. The same file becomes the GitHub release description.
3. `./scripts/release.sh`, on `main`.
4. Done: installed copies update themselves within about an hour (GitHub caches the
   feed for five minutes, Sparkle checks hourly and installs as soon as no call is
   being recorded). «Обновления» in the menu bar popover
   forces a check.

The script makes a release build, signs the zip with the EdDSA key from this Mac's
keychain, rewrites `appcast.xml` at the repo root, commits it, tags the commit
`v<version>`, pushes `main` with the tag and publishes the zip as a GitHub release in
`arhangel66/beseda`. It runs `swift test` first, and refuses to start at all unless it
is on `main`, the tag is still free, the working tree is clean and the notes file
exists, so every release matches a commit and describes itself. The `main` check
matters: the appcast commit lands on the current branch while the push targets
`main`, so a release cut elsewhere would publish a tag and a zip that no installed
copy is ever offered, without any command failing.

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
