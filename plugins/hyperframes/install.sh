#!/usr/bin/env bash
# Provision the HyperFrames CLI and everything it renders with: Node.js 22+,
# the `hyperframes` npm package, FFmpeg/FFprobe, and the pinned Chrome build
# (plus the shared libraries that Chrome needs on Linux). Idempotent — run it
# again to upgrade to $HYPERFRAMES_VERSION.
#
# Every step prefers what is already here, then a distro package when root is
# available without a password (`sudo -n`, never plain sudo — this also runs
# under the migration wizard, where a password prompt just hangs), then a copy
# the plugin owns under state/, which is always writable.
#
# npm runs with the server user's real home (cache and ~/.npmrc, so a private
# registry works and reinstalls are warm). Chrome is fetched with the plugin's
# home, because that is where `hyperframes` looks for it at run time — see lib.sh.
set -uo pipefail

state="${PLUGIN_STATE_DIR:?PLUGIN_STATE_DIR is not set}"
version="${HYPERFRAMES_VERSION:-latest}"
mkdir -p "$state"

# --- Root without asking, and system packages ---------------------------------
apt_refreshed=0
sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then sudo -n "$@"
  else return 1
  fi
}
can_root() { [ "$(id -u)" -eq 0 ] || { command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; }; }

# Install one or more packages; non-zero if any could not be installed.
system_install() {
  can_root || return 1
  if command -v apt-get >/dev/null 2>&1; then
    if ! sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1; then
      [ "$apt_refreshed" -eq 1 ] && return 1
      apt_refreshed=1
      sudo_cmd apt-get update -qq >/dev/null 2>&1
      sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1 || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then sudo_cmd dnf install -y -q "$@" >/dev/null 2>&1 || return 1
  elif command -v yum >/dev/null 2>&1; then sudo_cmd yum install -y -q "$@" >/dev/null 2>&1 || return 1
  elif command -v apk >/dev/null 2>&1; then sudo_cmd apk add --quiet "$@" >/dev/null 2>&1 || return 1
  else return 1
  fi
  hash -r 2>/dev/null || true
}

# --- A downloader -------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "Neither curl nor wget is installed; trying to install curl."
  system_install curl || true
fi
download() { # url dest
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else return 1
  fi
}
fetch() { # url -> stdout
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O - "$1"
  else return 1
  fi
}

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) node_arch=linux-x64; ffmpeg_arch=amd64 ;;
  Linux/aarch64 | Linux/arm64) node_arch=linux-arm64; ffmpeg_arch=arm64 ;;
  Darwin/x86_64) node_arch=darwin-x64; ffmpeg_arch="" ;;
  Darwin/arm64) node_arch=darwin-arm64; ffmpeg_arch="" ;;
  *) node_arch=""; ffmpeg_arch="" ;;
esac

# Directories that end up on PATH for every script, in priority order.
path_dirs=()
env_lines=()

# --- Node.js 22+ ----------------------------------------------------------------
node_major() { "${1:-node}" -p 'process.versions.node.split(".")[0]' 2>/dev/null; }
node_ok() { local m; m="$(node_major "$1")"; [ -n "$m" ] && [ "$m" -ge 22 ]; }

own_node="$state/node"
if [ -x "$own_node/bin/node" ] && node_ok "$own_node/bin/node"; then
  echo "Using the plugin's own Node.js $("$own_node/bin/node" --version)."
  path_dirs+=("$own_node/bin")
elif command -v node >/dev/null 2>&1 && node_ok node && command -v npm >/dev/null 2>&1; then
  echo "Using Node.js $(node --version) at $(command -v node)."
  # Recorded, so commands find this node even when the server starts with a
  # different PATH (an nvm node, say).
  path_dirs+=("$(dirname "$(command -v node)")")
else
  [ -n "$node_arch" ] || { echo "No Node.js 22+ here, and no Node.js build is published for $(uname -s)/$(uname -m)." >&2; exit 1; }
  echo "Node.js 22+ is not available (found: $(node --version 2>/dev/null || echo none)); downloading Node.js 22 into the plugin."
  dist="https://nodejs.org/dist/latest-v22.x"
  sums="$(fetch "$dist/SHASUMS256.txt")" || { echo "Could not reach $dist." >&2; exit 1; }
  line="$(printf '%s\n' "$sums" | grep " node-v[0-9.]*-$node_arch\.tar\.gz\$" | head -1)"
  [ -n "$line" ] || { echo "No $node_arch tarball listed in $dist/SHASUMS256.txt." >&2; exit 1; }
  sha="${line%% *}"
  file="${line##* }"
  tmp="$state/.node-download"
  rm -rf "$tmp" && mkdir -p "$tmp"
  download "$dist/$file" "$tmp/$file" || { echo "Could not download $dist/$file." >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$tmp/$file" | cut -d' ' -f1)"
  else got="$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1)"
  fi
  [ "$got" = "$sha" ] || { echo "Checksum mismatch for $file; not installing it." >&2; rm -rf "$tmp"; exit 1; }
  tar -xzf "$tmp/$file" -C "$tmp" || { echo "Could not unpack $file." >&2; exit 1; }
  rm -rf "$own_node"
  mv "$tmp/${file%.tar.gz}" "$own_node"
  rm -rf "$tmp"
  echo "Installed Node.js $("$own_node/bin/node" --version) to $own_node."
  path_dirs+=("$own_node/bin")
fi
[ -x "$own_node/bin/node" ] && node_ok "$own_node/bin/node" && export PATH="$own_node/bin:$PATH"

# --- The hyperframes CLI --------------------------------------------------------
real_home="${PLUGIN_REAL_HOME:-$HOME}"
npm_env() {
  env HOME="$real_home" npm_config_cache="$real_home/.npm" npm_config_userconfig="$real_home/.npmrc" "$@"
}

# A prefix npm can really write into: test lib/node_modules (and an existing
# hyperframes package inside it), not just the top level — a prefix whose
# packages were installed with sudo looks writable and fails halfway through.
usable_prefix() {
  local p="$1"
  [ -n "$p" ] || return 1
  mkdir -p "$p/lib/node_modules" 2>/dev/null || return 1
  [ -w "$p/lib/node_modules" ] || return 1
  [ ! -d "$p/lib/node_modules/hyperframes" ] || [ -w "$p/lib/node_modules/hyperframes" ] || return 1
}

prefix=""
# The plugin's own prefix is last, and is why this cannot come up empty.
for candidate in \
  "$(npm_env npm config get prefix 2>/dev/null)" \
  /usr/local/share/npm-global \
  "$state/npm-global"; do
  if usable_prefix "$candidate"; then prefix="$candidate"; break; fi
done
[ -n "$prefix" ] || { echo "No writable npm prefix, not even $state/npm-global — check that directory's permissions." >&2; exit 1; }

echo
echo "Installing hyperframes@$version into $prefix (a minute or two)..."
if ! npm_env npm install -g --no-fund --no-audit --prefix "$prefix" "hyperframes@$version"; then
  if command -v hyperframes >/dev/null 2>&1; then
    echo "The install failed; keeping the hyperframes CLI already at $(command -v hyperframes)." >&2
    prefix="$(cd "$(dirname "$(command -v hyperframes)")/.." && pwd)"
  else
    echo "Installing hyperframes@$version failed and no working CLI is present." >&2
    exit 1
  fi
fi
path_dirs=("$prefix/bin" ${path_dirs[@]+"${path_dirs[@]}"})
export PATH="$prefix/bin:$PATH"
# npm's prefix, so `npx hyperframes ...` (as the upstream docs write it) finds
# this install instead of fetching another copy.
env_lines+=("export npm_config_prefix=\"$prefix\"")
hyperframes --version >/dev/null 2>&1 || { echo "Installed into $prefix/bin, but hyperframes does not run." >&2; exit 1; }
pkg_dir="$(dirname "$(dirname "$(readlink -f "$(command -v hyperframes)")")")"
cli_version="$(node -p "require('$pkg_dir/package.json').version" 2>/dev/null)"
echo "Installed hyperframes ${cli_version:-(unknown version)}."

# --- The upstream skills, matched to this CLI ---------------------------------
# GUIDELINE.md is the plugin's own digest; the deep references are HyperFrames'
# own skills. The npm package ships three of them (with their helper scripts)
# in dist/skills, so they always match the installed CLI. The registry skill is
# not in the package and is fetched from the same release tag — best effort,
# the guideline covers its essentials.
skills="$state/skills"
rm -rf "$skills" && mkdir -p "$skills"
for s in "$pkg_dir"/dist/skills/*/; do
  [ -f "$s/SKILL.md" ] && ln -s "${s%/}" "$skills/$(basename "$s")"
done
fetch_registry_skill() {
  [ -n "$cli_version" ] || return 1
  local api="https://api.github.com/repos/heygen-com/hyperframes/contents/skills/hyperframes-registry"
  local dir list path
  for dir in "" references; do
    list="$(fetch "$api${dir:+/$dir}?ref=v$cli_version")" || return 1
    mkdir -p "$skills/hyperframes-registry${dir:+/$dir}"
    printf '%s' "$list" | node -e '
      let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        for (const f of JSON.parse(s)) if (f.type === "file" && f.name.endsWith(".md")) console.log(f.path);
      });' | while read -r path; do
      download "https://raw.githubusercontent.com/heygen-com/hyperframes/v$cli_version/$path" \
        "$skills/${path#skills/}" || return 1
    done || return 1
  done
}
if ! fetch_registry_skill; then
  rm -rf "$skills/hyperframes-registry"
  echo "Could not fetch the hyperframes-registry skill for v$cli_version from GitHub; GUIDELINE.md covers it."
fi
echo "Skills for this CLI: $(cd "$skills" && echo *) (in \$HYPERFRAMES_SKILLS_DIR)."
env_lines+=("export HYPERFRAMES_SKILLS_DIR=\"$skills\"")

# --- FFmpeg and FFprobe -----------------------------------------------------------
echo
own_ffmpeg="$state/ffmpeg"
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  echo "Using FFmpeg at $(command -v ffmpeg)."
elif [ -x "$own_ffmpeg/ffmpeg" ] && [ -x "$own_ffmpeg/ffprobe" ]; then
  echo "Using the plugin's own FFmpeg at $own_ffmpeg."
else
  echo "FFmpeg is not installed; trying the distro package."
  if ! system_install ffmpeg || ! command -v ffprobe >/dev/null 2>&1; then
    [ -n "$ffmpeg_arch" ] || { echo "Could not install FFmpeg, and no static build is fetched for $(uname -s)/$(uname -m)." >&2; exit 1; }
    command -v xz >/dev/null 2>&1 || system_install xz-utils || system_install xz || true
    url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-$ffmpeg_arch-static.tar.xz"
    echo "No root for a package; downloading a static FFmpeg build from $url"
    tmp="$state/.ffmpeg-download"
    rm -rf "$tmp" && mkdir -p "$tmp"
    if download "$url" "$tmp/ffmpeg.tar.xz" && tar -xJf "$tmp/ffmpeg.tar.xz" -C "$tmp"; then
      rm -rf "$own_ffmpeg" && mkdir -p "$own_ffmpeg"
      mv "$tmp"/ffmpeg-*-static/ffmpeg "$tmp"/ffmpeg-*-static/ffprobe "$own_ffmpeg/"
      rm -rf "$tmp"
      echo "Installed static FFmpeg to $own_ffmpeg."
    else
      rm -rf "$tmp"
      echo "Could not install FFmpeg: no distro package (needs root or password-less sudo)" >&2
      echo "and the static download from $url failed (it needs xz to unpack)." >&2
      exit 1
    fi
  fi
fi
if [ -x "$own_ffmpeg/ffmpeg" ] && ! command -v ffmpeg >/dev/null 2>&1; then
  path_dirs+=("$own_ffmpeg")
  env_lines+=("export HYPERFRAMES_FFMPEG_PATH=\"$own_ffmpeg/ffmpeg\"" "export HYPERFRAMES_FFPROBE_PATH=\"$own_ffmpeg/ffprobe\"")
  export PATH="$own_ffmpeg:$PATH"
fi

# --- Record it ------------------------------------------------------------------
{
  printf 'export PATH="%s:$PATH"\n' "$(IFS=:; echo "${path_dirs[*]}")"
  for l in "${env_lines[@]}"; do printf '%s\n' "$l"; done
} >"$state/env.sh"
echo
echo "Recorded the tool paths in \$PLUGIN_STATE_DIR/env.sh."

# --- Chrome -----------------------------------------------------------------------
# From here on, run as the plugin's commands will: lib.sh's environment, the
# plugin's HOME (so the Chrome lands where run.sh looks for it).
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

# The CLI unpacks its Chrome download with unzip when it is there (it has a
# slower fallback), so best effort only.
command -v unzip >/dev/null 2>&1 || system_install unzip || true

echo
echo "Fetching the pinned Chrome build..."
if ! hyperframes browser ensure; then
  echo "Could not download Chrome. Local check, snapshot and render will not work;" >&2
  echo "lint and 'hyperframes cloud render' (with a HeyGen sign-in) still do." >&2
fi

# A Chrome on disk is not a Chrome that starts: on a bare Linux server the
# headless shell's shared libraries are usually missing. Install them when root
# is free; otherwise say exactly what is missing.
chrome="$(hyperframes browser path 2>/dev/null | tail -1)"
missing_libs() { [ -x "$chrome" ] && command -v ldd >/dev/null 2>&1 && ldd "$chrome" 2>/dev/null | grep 'not found'; }
if [ "$(uname -s)" = Linux ] && [ -n "$(missing_libs)" ]; then
  echo "Chrome is missing shared libraries; installing them."
  if command -v apt-get >/dev/null 2>&1; then
    debs=(libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libatspi2.0-0
      libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2)
    system_install "${debs[@]}" libasound2t64 || system_install "${debs[@]}" libasound2 || true
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    system_install nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon at-spi2-core libXcomposite \
      libXdamage libXfixes libXrandr mesa-libgbm pango cairo alsa-lib || true
  elif command -v apk >/dev/null 2>&1; then
    system_install nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon at-spi2-core libxcomposite \
      libxdamage libxfixes libxrandr mesa-gbm pango cairo alsa-lib || true
  fi
  if [ -n "$(missing_libs)" ]; then
    echo "Chrome still cannot load:" >&2
    missing_libs | sed 's/^/  /' >&2
    echo "Installing them needs root (no root and no password-less sudo here). Until an" >&2
    echo "administrator installs them, local check/snapshot/render fail; lint and cloud render work." >&2
  fi
fi
# Fonts video text falls back to (emoji, CJK). Best effort, never fatal.
if [ "$(uname -s)" = Linux ] && command -v apt-get >/dev/null 2>&1 && can_root; then
  system_install fonts-liberation fonts-noto-color-emoji fonts-noto-cjk >/dev/null 2>&1 || true
fi

# --- Report -------------------------------------------------------------------------
# Docker, Kokoro, MusicGen and whisper show as missing on most servers; they
# are optional extras, not install failures.
hyperframes doctor || true
echo
echo "Installed. Signing in to HeyGen is optional: local authoring and rendering work without it."
