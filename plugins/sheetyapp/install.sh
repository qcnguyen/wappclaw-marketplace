#!/usr/bin/env bash
# Provision the shp CLI into the plugin's own state/bin.
#
# shp is a single self-contained binary published per platform at
# $SHP_DOWNLOAD_URL/<rid>/shp, so there is no package manager and nothing needs
# root: the copy the plugin owns is the only install, and state/ is always
# writable. Idempotent — run it again to upgrade to the latest published build.
#
# Deliberately does NOT source lib.sh: it writes the env.sh that lib.sh reads.
set -euo pipefail

state="${PLUGIN_STATE_DIR:?PLUGIN_STATE_DIR is not set}"
base="${SHP_DOWNLOAD_URL:-https://cdn.sheetyapp.com/cli}"
base="${base%/}"
bin_dir="$state/bin"
mkdir -p "$bin_dir"

# --- Platform --------------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"
case "$os/$arch" in
  Linux/x86_64) rid=linux-x64 ;;
  Linux/aarch64 | Linux/arm64) rid=linux-arm64 ;;
  Darwin/x86_64) rid=osx-x64 ;;
  Darwin/arm64) rid=osx-arm64 ;;
  *)
    echo "shp is not published for $os/$arch (published: linux-x64, linux-arm64, osx-x64, osx-arm64)." >&2
    exit 1
    ;;
esac

# --- A downloader ------------------------------------------------------------
# curl, else wget. If neither is here, install curl — but only as root or with a
# password-less sudo: plain sudo would wait for a password nobody is there to type.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo -n "$@"
  else return 1
  fi
}

ensure_downloader() {
  command -v curl >/dev/null 2>&1 && return 0
  command -v wget >/dev/null 2>&1 && return 0
  echo "Neither curl nor wget is installed; trying to install curl."
  if command -v apt-get >/dev/null 2>&1; then
    as_root apt-get install -y curl >/dev/null 2>&1 ||
      { as_root apt-get update >/dev/null 2>&1 && as_root apt-get install -y curl >/dev/null 2>&1; } || true
  elif command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y curl >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    as_root apk add --no-cache curl >/dev/null 2>&1 || true
  fi
  command -v curl >/dev/null 2>&1 && return 0
  echo "Could not get a downloader: no curl or wget, and installing curl failed" >&2
  echo "(tried apt-get/dnf/apk as root or with password-less sudo). Install curl on" >&2
  echo "this server and run Install again." >&2
  return 1
}

download() { # url dest
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 "$1" -o "$2"
  else wget -q -O "$2" "$1"
  fi
}

# --- Download --------------------------------------------------------------
url="$base/$rid/shp"
tmp="$bin_dir/.shp.download"
rm -f "$tmp"

# Whatever PATH this script started with, plus our own bin — for the fallback.
existing=""
if [ -x "$bin_dir/shp" ]; then existing="$bin_dir/shp"
elif command -v shp >/dev/null 2>&1; then existing="$(command -v shp)"
fi

if ! ensure_downloader || ! { echo "Downloading shp ($rid) from $url"; download "$url" "$tmp"; }; then
  rm -f "$tmp"
  if [ -n "$existing" ]; then
    echo "Download failed; keeping the shp already installed at $existing." >&2
    printf 'export PATH="%s:$PATH"\n' "$(dirname "$existing")" >"$state/env.sh"
    exit 0
  fi
  echo "Could not download shp from $url." >&2
  exit 1
fi
chmod +x "$tmp"

# --- Check it runs here ------------------------------------------------------
# The binary is self-contained .NET. On a server without ICU (libicu) it aborts
# at start-up; invariant globalization is the documented switch for that, and
# shp formats nothing culture-specific that the agent would miss.
env_extra=""
# In a child bash with its stderr dropped: an abort is reported by the shell that
# waits for the process ("Aborted (core dumped)"), and that line is just noise.
# The trailing `exit` stops bash from exec-ing the binary in its own place.
probe() { bash -c '"$0" --help >/dev/null 2>"$1"; exit $?' "$tmp" "$state/install-check.err" 2>/dev/null; }
if ! probe; then
  if grep -qi 'icu' "$state/install-check.err" &&
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 "$tmp" --help >/dev/null 2>&1; then
    echo "libicu is not installed here; running shp with invariant globalization."
    env_extra='export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1'
  else
    echo "The downloaded shp does not run on this machine:" >&2
    sed 's/^/  /' "$state/install-check.err" >&2
    rm -f "$tmp"
    exit 1
  fi
fi
rm -f "$state/install-check.err"

mv -f "$tmp" "$bin_dir/shp"

{
  printf 'export PATH="%s:$PATH"\n' "$bin_dir"
  [ -n "$env_extra" ] && printf '%s\n' "$env_extra"
} >"$state/env.sh"

echo "Installed shp to $bin_dir/shp."
echo "Next: Authenticate, then delegate workbooks to the CLI in the SheetyApp web app"
echo "(workbook Settings -> Connected Apps -> client 'cli')."
