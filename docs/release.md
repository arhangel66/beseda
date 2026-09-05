# Releasing

1. Bump `VERSION`.
2. `./scripts/release_podushka.sh`.
3. Done: installed copies update themselves within an hour (Sparkle checks hourly and
   installs as soon as no call is being recorded). «Обновления» in the menu bar popover
   forces a check.

The script makes a release build, signs the zip with the EdDSA key from this Mac's
keychain, publishes it as a GitHub release in `arhangel66/podushka` and rewrites
`appcast.xml` at that repo's root. It refuses to run when the tag already exists.

The dev loop (`scripts/build_podushka_app.sh`, `scripts/package_podushka.sh`) never
carries the Sparkle keys, so a dev build does not update itself. Only a release build
does; the keys are written by `scripts/lib/bundle_app.sh` for the `release` flavour.

## The signing key

`generate_keys` created one EdDSA key pair; the private half sits in the login
keychain of Mikhail's Mac, the public half is in `bundle_app.sh`. Losing the private
key means no installed copy can ever be updated again, so keep a backup:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/podushka-sparkle-key.txt
```

Put that file into 1Password and delete it from the disk.

## The first Sparkle-enabled version

A copy older than 0.2.1 has no updater: install it by hand once as described in
`install.md`. Sparkle skips its scheduled check on the very first launch of a bundle,
so the first automatic update arrives after the second launch or a manual check.
