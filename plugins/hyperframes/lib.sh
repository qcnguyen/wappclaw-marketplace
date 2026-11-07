# Shared preamble for the hyperframes scripts. Sourced, never executed.
#
# install.sh provisions Node 22+, the hyperframes CLI, FFmpeg and the pinned
# Chrome, and records where each one landed in state/env.sh (PATH, npm's prefix,
# HYPERFRAMES_FFMPEG_PATH/FFPROBE_PATH when it had to fetch its own FFmpeg), so
# every script runs what the install actually produced.
if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# **Everything the CLI keeps is the plugin's own.** The HeyGen sign-in
# (~/.hyperframes/credentials), the pinned Chrome (~/.cache/hyperframes) and the
# media ledger all resolve from $HOME, and the platform points HOME at
# state/home/ for every script. So a `hyperframes` run from the plain shell is a
# different, signed-out CLI with no Chrome of its own.
#
# Sourced by install.sh's Chrome step, auth.sh, auth-status.sh and run.sh, which
# must agree on that home: a Chrome or a login written under one home and read
# under another is never found.

# The plugin owns which CLI is installed (Reinstall upgrades it), and the skills
# the CLI would otherwise copy into every project it scaffolds are already in
# reference/. So: no update nags, and `init` leaves .claude/ alone.
export HYPERFRAMES_NO_UPDATE_CHECK=1
export HYPERFRAMES_SKIP_SKILLS=1
[ "${HYPERFRAMES_TELEMETRY:-on}" = "off" ] && export HYPERFRAMES_NO_TELEMETRY=1

# One credential at a time. The CLI reads HEYGEN_API_KEY before its stored
# OAuth session, so in device-code mode a key left in the secret store would
# silently win over the account an administrator signed in with, and in local
# mode it would quietly enable HeyGen features nobody asked for.
if [ "${HEYGEN_AUTH_MODE:-local}" != "apiKey" ]; then
  unset HEYGEN_API_KEY
fi

require_hyperframes() {
  command -v hyperframes >/dev/null 2>&1 && return 0
  echo "The hyperframes CLI is not available. Install the plugin from the admin app first." >&2
  return 1
}
