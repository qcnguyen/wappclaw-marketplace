#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means signed in, in the mode
# this plugin is configured for.
#
# **Do not trust `m365 status`'s exit code**: it is 0 whether signed in or not
# (`m365 status --output json` prints the bare string `"Logged out"` and exits 0).
# A probe that returned `$?` therefore reported "signed in" always, which is
# exactly what the admin page showed while the plugin was logged out. So the
# *output* is what decides: `connectedAs` appears only in a real connection.
#
# **And the connection has to be the configured one.** The CLI can hold several
# connections at once, so a certificate plugin can be sitting on a device-code
# connection left over from before the mode was changed — signed in, as the wrong
# identity, with the wrong permissions. `authType` in the same output says which,
# and a mismatch reads as not signed in: the sign-in this plugin is configured to
# have has not happened yet. Authenticating takes exactly that mode, so the light
# turns green for the right reason.
#
# Quiet on purpose — nothing reads this script's output, only its exit code.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

export CLIMICROSOFT365_PROMPT=false
command -v m365 >/dev/null 2>&1 || exit 1

out=$(m365 status --output json 2>/dev/null) || exit 1
case "$out" in
  *'"connectedAs"'*) ;;
  *) exit 1 ;;
esac

# `{"connectionName": "x", "authType": "deviceCode", ...}` -> `deviceCode`, with
# no jq: strip spaces and quotes, split on commas, take the field. An older CLI
# that does not report `authType` yields nothing here, and an empty answer is not
# evidence of a mismatch — `connectedAs` already said signed in, so leave it.
active=$(printf '%s' "$out" | tr -d ' \t"' | tr ',' '\n' | sed -n 's/^authType:\(.*\)$/\1/p' | head -1)
[ -n "$active" ] || exit 0

want="${CLIMICROSOFT365_AUTHTYPE:-deviceCode}"
[ "$active" = "$want" ] || exit 1
exit 0
