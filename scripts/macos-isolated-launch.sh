#!/usr/bin/env bash
# Source this file, then call launch_isolated_macos_app APP_PATH BUNDLE_ID [--clean-defaults].
# The call blocks until the app exits and never activates or orders the app to the front.

launch_isolated_macos_app() {
    if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$3" != "--clean-defaults" ]; }; then
        echo "usage: launch_isolated_macos_app APP_PATH BUNDLE_ID [--clean-defaults]" >&2
        return 64
    fi

    local app_path="$1" bundle_id="$2" home
    home="$(mktemp -d "${TMPDIR:-/tmp}/ios-kit-macos-home.XXXXXX")"
    trap 'rm -rf "$home"' RETURN

    # cfprefsd ignores CFFIXED_USER_HOME. Delete the run-specific domain on both sides of the launch.
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    if [ "${3:-}" = "--clean-defaults" ]; then
        open -W -n -g -j --env CFFIXED_USER_HOME="$home" --env IOS_KIT_CLEAN_DEFAULTS=1 "$app_path"
    else
        open -W -n -g -j --env CFFIXED_USER_HOME="$home" "$app_path"
    fi
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
}
