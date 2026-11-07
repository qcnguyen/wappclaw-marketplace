#!/usr/bin/env bash
# Run one command with Jira credentials in place.
#
# The command arrives in the environment (PLUGIN_COMMAND) and on stdin as JSON —
# never on this script's command line — and is executed **as written**. That
# verbatim contract is what lets the guideline document the real REST API rather
# than a translation nobody can debug through.
#
# What this adds is only environment, which is the whole reason the plugin exists
# rather than the agent curling Jira itself:
#   - the credential, in a `.netrc` curl finds on its own, so `curl -n` is
#     authenticated and no token appears in the command or its output
#   - `$JIRA_BASE`, the gateway URL for this site, which is not guessable
#
# Nothing here decides where the command runs: the platform has already put this
# process in the directory the caller asked for, or in the turn's own scratch
# folder when it named none.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_curl || exit 1

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the Jira REST API vocabulary." >&2
  exit 2
fi

jira_check_config || exit 2
jira_resolve_base || exit 1

# Rewritten per command, so a token rotated in the admin app takes effect on the
# next call rather than at the next Authenticate.
jira_write_netrc || {
  echo "Could not write the credential file for this command." >&2
  exit 1
}

export JIRA_BASE JIRA_CLOUD_ID
export JIRA_SITE_URL="https://$(jira_host)"

# **Drop the raw token before running anything.** The command reaches Jira through
# the netrc, so it has no need of the token itself — and a command that dumps its
# own environment then leaks nothing.
unset JIRA_API_TOKEN

# Run the command under default shell semantics, not this script's: `pipefail`
# would turn `… | head -5` into exit 141 (SIGPIPE) and report a command that did
# exactly what was asked as a failure.
set +u +o pipefail

# `eval` because a command is a command: a JQL query and a JSON body are full of
# spaces and quotes, and word-splitting them would break every one of them.
eval "$command_text"
