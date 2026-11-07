#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means usable. Silent by design.
#
# `az account get-access-token`, not `az account show`: `show` answers from the
# local config, so a principal whose secret was revoked yesterday still has an
# account on disk and `show` still exits 0 — a probe built on it stays green
# through the whole outage. Getting a token requires Entra to agree.
#
# Its output is discarded because it prints a live access token.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

command -v az >/dev/null 2>&1 || exit 1
[ -n "${AZ_CLIENT_ID:-}" ]     || exit 1
[ -n "${AZ_TENANT_ID:-}" ]     || exit 1
[ -n "${AZ_CLIENT_SECRET:-}" ] || exit 1

# The chip must describe the **configured** credential, not whatever the last
# Authenticate happened to store — so bring the stored login into step first.
az_ensure_login >/dev/null 2>&1 || true
az_usable
