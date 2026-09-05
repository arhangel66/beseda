# Podushka Resources

`Info.plist` is copied into the local `.app` wrapper by `scripts/build_podushka_app.sh`.

`AppIcon.icon` is the Icon Composer source of the app icon — the blue tile with the waveform
from the design. The build script compiles it with `actool`; it is not used at runtime as is.
