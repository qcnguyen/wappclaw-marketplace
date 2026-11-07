#!/usr/bin/env bash
# Check the tools this plugin drives, install what is missing, and prepare its
# working directory.
#
# There is usually nothing to download: git and curl are on any box that could run
# this server. So this script's job is mostly the other half of an install —
# proving the environment can actually do what the plugin promises, at a moment
# when a human is watching the output, rather than at the moment the agent first
# tries.
#
# Where something *is* missing it is installed here rather than described. This
# runs under the migration wizard against servers nobody has logged into, so a
# step that ends in "install this and press the button again" is a step that has
# failed — see `system_install`.
#
# Deliberately does not source lib.sh: it needs no credential and no token, and
# an install that fails because nobody has configured a secret yet would be
# telling the admin off for doing things in the normal order.
set -uo pipefail

# Whether `apt-get update` has already been paid for in this run: a fresh image
# often has no package lists, and refreshing them is slow enough to be worth
# doing once, lazily, and only when an install has actually failed without it.
apt_refreshed=0

# Install a system package, but only when that can happen without a human: as
# root already, or with password-free sudo. `sudo -n` fails instead of prompting,
# which is what makes this safe to call unattended — there is no terminal here for
# anyone to type a password into, so a prompt would just hang until the session's
# timeout. Returns non-zero when the package could not be installed, for any
# reason; the caller decides whether that is fatal.
system_install() {
  local pkg="$1" bin="${2:-$1}" sudo_cmd
  if [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=""
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo_cmd="sudo -n"
  else
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    if ! DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
      [ "$apt_refreshed" -eq 1 ] && return 1
      apt_refreshed=1
      $sudo_cmd apt-get update -qq >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1 || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    $sudo_cmd dnf install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v yum >/dev/null 2>&1; then
    $sudo_cmd yum install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v apk >/dev/null 2>&1; then
    $sudo_cmd apk add --quiet "$pkg" >/dev/null 2>&1 || return 1
  else
    return 1
  fi

  hash -r 2>/dev/null || true
  command -v "$bin" >/dev/null 2>&1
}

fail=0

echo "Checking the tools this plugin needs."
echo

# --- git, and specifically a git new enough for env-injected config ----------
#
# The whole credential mechanism is `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`, added
# in git 2.31 (March 2021). On anything older the token would have to go on the
# command line, where `ps` publishes it to every account on the machine — so this
# is a hard requirement, not a preference.
if ! command -v git >/dev/null 2>&1; then
  echo "  git: not found — installing it..."
  system_install git >/dev/null 2>&1 || true
fi
if ! command -v git >/dev/null 2>&1; then
  echo "  git: NOT FOUND, and it could not be installed automatically." >&2
  echo "      Installing git needs root, which this server does not have (no root," >&2
  echo "      and no password-free sudo). An administrator has to run one of:" >&2
  echo "          apt-get install git / dnf install git" >&2
  fail=1
else
  git_version=$(git --version | awk '{print $3}')
  git_major=${git_version%%.*}
  git_rest=${git_version#*.}
  git_minor=${git_rest%%.*}
  echo "  git:  $git_version  ($(command -v git))"
  if [ "$git_major" -lt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -lt 31 ]; }; then
    echo "      TOO OLD. This plugin needs git 2.31 or newer, which is the first version" >&2
    echo "      that accepts configuration through the environment (GIT_CONFIG_COUNT)." >&2
    echo "      Older git can only take the access token as a command-line argument," >&2
    echo "      where /proc/<pid>/cmdline exposes it to every user on this machine." >&2
    fail=1
  fi
fi

# --- curl, which mints the token --------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  echo "  curl: not found — installing it..."
  system_install curl >/dev/null 2>&1 || true
fi
if command -v curl >/dev/null 2>&1; then
  echo "  curl: $(curl --version | head -1 | awk '{print $2}')  ($(command -v curl))"
else
  echo "  curl: NOT FOUND, and it could not be installed automatically." >&2
  echo "      Needed to exchange the service principal's secret for an access token." >&2
  echo "      Installing it needs root, which this server does not have." >&2
  fail=1
fi

# --- jq, which is only ever cosmetic ----------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  system_install jq >/dev/null 2>&1 || true
fi
if command -v jq >/dev/null 2>&1; then
  echo "  jq:   $(jq --version)  (used to read JSON responses)"
else
  echo "  jq:   not found — fine. A fallback parser is used; only the formatting suffers."
fi

# --- git-lfs, because a repository that needs it needs it silently -----------
#
# Installed rather than recommended: without it a clone *succeeds* and leaves
# pointer files where the binaries should be, which is the kind of failure nobody
# notices until something downstream reads one.
if ! command -v git-lfs >/dev/null 2>&1; then
  echo "  git-lfs: not found — installing it (LFS repositories clone as pointer files"
  echo "           without it)..."
  if system_install git-lfs >/dev/null 2>&1; then
    # `git lfs install` writes filters into the *plugin's* git config, because
    # HOME is the plugin's at run time. Doing it here means a clone that needs
    # LFS just works instead of needing a first-use setup step.
    git lfs install --skip-repo >/dev/null 2>&1 || true
  fi
fi
if command -v git-lfs >/dev/null 2>&1; then
  echo "  git-lfs: $(git-lfs version 2>/dev/null | head -1)"
else
  echo "  git-lfs: not found, and it could not be installed automatically (that needs"
  echo "           root). Repositories that store binaries in LFS will clone their"
  echo "           pointers but not their contents."
fi

echo

# --- an identity for commits -------------------------------------------------
#
# The token authorises the *push*; `user.name`/`user.email` name the *author*, and
# git refuses to commit without them. They come from this plugin's own settings and
# nowhere else: `HOME` is the plugin's, so the server user's `~/.gitconfig` is not
# read, and that is deliberate — who this plugin commits as is a property of the
# plugin, not of whoever owns the box.
commit_name="${AZDO_COMMIT_NAME:-}"
commit_email="${AZDO_COMMIT_EMAIL:-}"

if [ -n "$commit_email" ] && [ -n "$commit_name" ]; then
  echo "Commit identity: $commit_name <$commit_email>"
  echo "  From this plugin's settings, injected per command. The machine's git"
  echo "  configuration is neither read nor modified."
elif [ -n "$commit_email" ] || [ -n "$commit_name" ]; then
  echo "Commit identity is only half set: ${commit_name:-<no name>} <${commit_email:-no email}>" >&2
  echo "  git needs BOTH. Set the missing one in the admin app, or commits will fail." >&2
else
  echo "No commit identity configured."
  echo "  Cloning, fetching, reading and pushing an existing commit all work."
  echo "  Making a commit will fail with 'Author identity unknown' until someone sets"
  echo "  'Commit author name' and 'Commit author email' in this plugin's settings."
fi
echo "  The author is who a commit is *by*; the push is authorised as the service"
echo "  principal regardless. They are separate, and both have to be right."

echo

# --- where checkouts go ------------------------------------------------------
#
# Nowhere this plugin decides. There is deliberately no setting for it: the caller
# says where it wants to work, in the command, because it is the caller that knows
# where its files belong. All the install has to check is that the floor exists.
work="${PLUGIN_STATE_DIR:-.}/work"
if mkdir -p "$work" 2>/dev/null; then
  echo "Checkout location: whatever the command says."
  echo "  This plugin has no default location and no setting for one — a command gives an"
  echo "  absolute path (e.g. 'cd /abs/path && git clone <url>')."
  echo "  A command that writes to a relative path instead gets a throwaway directory"
  echo "  under $work, and the command's output says where its files ended up."
else
  echo "Could not create $work" >&2
  echo "  The plugin needs it as a fallback working directory. Check the permissions on" >&2
  echo "  the plugin's state folder." >&2
  fail=1
fi

# Nothing needs to go on PATH today. The file is still written, because every
# other script sources it and a plugin that later provisions a binary should have
# one obvious place to record it.
if [ -n "${PLUGIN_STATE_DIR:-}" ]; then
  mkdir -p "$PLUGIN_STATE_DIR"
  printf '# Sourced by lib.sh before every command.\n# Nothing to add: git and curl come from the system.\n' \
    > "$PLUGIN_STATE_DIR/env.sh"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "Install incomplete — fix the items marked above and run it again." >&2
  exit 1
fi

echo "Ready."
echo
echo "Next, in the admin app:"
echo "  1. Settings — set the service principal client ID, the Entra tenant ID and the"
echo "     Azure DevOps organisation, then store the service principal secret."
echo "  2. Authenticate — checks the credentials really work and that the service"
echo "     principal can see the organisation. Nothing interactive: it takes a second."
echo
echo "  Optionally set 'Commit author name' and 'Commit author email' as well, if commits"
echo "  made through this plugin should not carry this machine's git identity."
