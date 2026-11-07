#!/usr/bin/env bash
# Run one command with Azure DevOps credentials in place.
#
# The command arrives in the environment (PLUGIN_COMMAND) and on stdin as JSON —
# never on this script's command line — and is executed **as written**. That
# verbatim contract is what lets the guideline document real git rather than a
# translation nobody can debug through.
#
# What this script adds is only environment, which is the whole reason the plugin
# exists rather than the agent shelling out:
#   - a freshly minted Azure DevOps access token, in git's config for this process
#   - a working directory that is not the plugin's own bundle
#   - the machine's credential helper neutralised, so nothing else answers first
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for what this plugin can run." >&2
  exit 2
fi

azdo_check_config || exit 2

# A token per command. It lives for an hour, which is longer than all but the
# largest clone, and nothing is written to disk — so there is no cache to go
# stale, no file to leak, and a rotated secret takes effect on the next command
# rather than whenever something happened to expire.
token=$(azdo_token 25) || exit 1

# Resolved only to know which hosts to attach the credential to.
azdo_resolve_org >/dev/null 2>&1 || true

azdo_export_git_env "$token"

# Nothing plugin-specific is put in front of the command: no helper function, no
# token variable, no vocabulary to learn. The command sees ordinary `git`, which
# happens to be authenticated. That is the whole product.

# **Drop the long-lived secret before running anything.** The command needs the
# one-hour token, never the credential that mints it — so the blast radius of a
# command that dumps its own environment (or of a hostile command) is one hour of
# Azure DevOps access rather than the service principal itself.
unset AZDO_CLIENT_SECRET

# **Nothing here decides where the command runs, and that is deliberate.** The
# platform has already put this process in the right directory — the one the
# caller asked for through `cwd`, or a throwaway one it owns when the caller named
# none — and reports afterwards if files were left in the latter. So there is no
# `cd`, no scratch directory of our own, and no setting: where output belongs is
# the caller's knowledge, and the one rule a plugin could get wrong (never write
# into your own bundle) is now guaranteed rather than remembered.

# **Run the agent's command under default shell semantics, not this script's.**
# `set -u` and `pipefail` protect the code above; applied to the command they
# misreport it. `pipefail` is the sharp one: `git ls-remote … | head -3` kills git
# with SIGPIPE the moment head has enough, so the pipeline exits 141 and a command
# that did exactly what was asked is reported to the agent as a failure. Piping a
# long listing into `head` or `jq` is the normal shape of a git command, so this
# would have been wrong more often than right.
set +u +o pipefail

# `eval` because a command is a command. Branch names, project names and paths in
# this organisation contain spaces and percent-escapes constantly, and
# word-splitting them would break every one of them.
eval "$command_text"
