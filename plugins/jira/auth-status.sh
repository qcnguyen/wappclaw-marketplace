#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means usable. Silent by design.
#
# It really calls Jira, rather than checking that a token is *present*. An API
# token can be revoked or expire, and a probe that only looked for a stored value
# would show a green chip through the whole outage. `/myself` is the cheapest
# authenticated endpoint there is, well inside the platform's 20s budget, and the
# answer is cached for 30s.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

command -v curl >/dev/null 2>&1 || exit 1
[ -n "${JIRA_SITE:-}" ]      || exit 1
[ -n "${JIRA_EMAIL:-}" ]     || exit 1
[ -n "${JIRA_API_TOKEN:-}" ] || exit 1

# Write the netrc first: the probe must test the credential that is *stored now*,
# not whatever the last Authenticate happened to leave on disk.
jira_write_netrc >/dev/null 2>&1 || exit 1
jira_usable >/dev/null 2>&1
