#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 = HeyGen accepts the
# credential of the configured mode. Silent: only the exit code is read.
#
# `hyperframes auth status` is safe to trust here, unlike most status commands:
# it verifies the credential against GET /v3/users/me and exits 1 when nobody
# is signed in or HeyGen rejects the credential.
#
# The mode matters too. lib.sh drops HEYGEN_API_KEY in device-code mode, so
# there only the stored OAuth session can pass; in API-key mode an absent key
# reads as signed out even if an old OAuth session is still on disk. Local mode
# has no credential to check, so it always passes: nothing is missing.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
command -v hyperframes >/dev/null 2>&1 || exit 1

[ "${HEYGEN_AUTH_MODE:-local}" = "local" ] && exit 0

if [ "${HEYGEN_AUTH_MODE:-local}" = "apiKey" ] && [ -z "${HEYGEN_API_KEY:-}" ]; then
  exit 1
fi

if command -v timeout >/dev/null 2>&1; then
  timeout 15 hyperframes auth status >/dev/null 2>&1
else
  hyperframes auth status >/dev/null 2>&1
fi
