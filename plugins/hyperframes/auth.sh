#!/usr/bin/env bash
# Sign this plugin in to HeyGen, in the mode the settings choose. Optional:
# local authoring and rendering need no account, so this only matters for
# cloud rendering and HeyGen media (music catalog, asset search, voices,
# avatars, generated images and video).
#
# Runs under a pty, which is what the CLI's `--device` flow requires (it refuses
# a non-attended terminal): it prints the URL and code immediately, then polls
# until a person approves it.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_hyperframes || exit 1

mode="${HEYGEN_AUTH_MODE:-local}"

# One credential at a time: drop the stored OAuth session left by an earlier
# sign-in, so it can't outlive a change of mode or account.
hyperframes auth logout >/dev/null 2>&1 || true

case "$mode" in
  local)
    echo "Sign-in mode is 'Local only': there is nothing to sign in to."
    echo "Any stored HeyGen session has been removed; local authoring and rendering work as-is."
    echo "Pick 'Device code' or 'API key' and Authenticate again to unlock cloud rendering and HeyGen media."
    exit 0
    ;;
  device)
    echo "Signing in to HeyGen with a device code."
    echo "Open the URL below and approve it with the HeyGen account this server should act as;"
    echo "cloud renders and HeyGen media are charged to that account's plan and credits."
    echo
    hyperframes auth login --device
    code=$?
    echo
    if [ "$code" -ne 0 ]; then
      echo "Sign-in did not complete (exit $code). If the code expired, run Authenticate again and approve it sooner." >&2
      exit "$code"
    fi
    ;;
  apiKey)
    if [ -z "${HEYGEN_API_KEY:-}" ]; then
      echo "The sign-in mode is 'API key', but no HeyGen API key is stored. Add it under this plugin's secrets." >&2
      exit 2
    fi
    # The CLI reads HEYGEN_API_KEY from the environment on every command, so
    # there is nothing to store — only to check that HeyGen accepts it.
    echo "Checking the HeyGen API key..."
    echo
    ;;
  *)
    echo "Unknown sign-in mode '$mode'." >&2
    exit 2
    ;;
esac

hyperframes auth status
