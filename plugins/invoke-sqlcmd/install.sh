#!/usr/bin/env bash
# Provision PowerShell 7 and the SqlServer module (which provides Invoke-Sqlcmd).
#
# Order, stopping at the first that works (see WRITING-A-PLUGIN.md):
#   1. a pwsh >= 7.2 already on PATH, or one a previous run put in state/
#   2. otherwise Microsoft's official tarball, unpacked into state/pwsh — needs no
#      root and no package repository, so it cannot fail for want of permission
# The SqlServer module always goes into state/modules, so the plugin's copy is
# its own and a Reinstall upgrades it.
#
# Idempotent: re-running upgrades the module and keeps a working pwsh.
set -uo pipefail

state="${PLUGIN_STATE_DIR:-${PLUGIN_DIR:-$(dirname "$0")}/state}"
mkdir -p "$state"
modules="$state/modules"
mkdir -p "$modules"

# Used when the GitHub API cannot be reached (rate limit, proxy).
PINNED_PWSH_VERSION='7.6.6'

export POWERSHELL_TELEMETRY_OPTOUT=1
export POWERSHELL_UPDATECHECK=Off

pwsh_ok() {
  local bin="$1" v major minor
  [ -x "$bin" ] || bin=$(command -v "$bin" 2>/dev/null) || return 1
  v=$("$bin" -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null) || return 1
  major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
  [ "${major:-0}" -gt 7 ] || { [ "${major:-0}" -eq 7 ] && [ "${minor:-0}" -ge 2 ]; }
}

# libicu is needed by .NET unless globalization is put in invariant mode.
icu_flag=""
if ! ldconfig -p 2>/dev/null | grep -q 'libicuuc\.so'; then
  icu_flag='export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1'
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
fi

echo "Checking PowerShell 7."
pwsh_bin=""
if pwsh_ok "$state/pwsh/pwsh"; then
  pwsh_bin="$state/pwsh/pwsh"
  echo "  pwsh: plugin copy, $("$pwsh_bin" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')  ($pwsh_bin)"
elif pwsh_ok pwsh; then
  pwsh_bin="$(command -v pwsh)"
  echo "  pwsh: system, $("$pwsh_bin" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')  ($pwsh_bin)"
else
  command -v curl >/dev/null 2>&1 || { echo "  curl is required to download PowerShell and is not installed." >&2; exit 1; }
  command -v tar  >/dev/null 2>&1 || { echo "  tar is required to unpack PowerShell and is not installed." >&2; exit 1; }

  case "$(uname -m)" in
    x86_64|amd64)  arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l)        arch=arm32 ;;
    *) echo "  Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  # Alpine and other musl distros need the musl build.
  if ldd --version 2>&1 | grep -qi musl; then flavour="linux-musl-$arch"; else flavour="linux-$arch"; fi

  version=$(curl -fsSL --max-time 20 https://api.github.com/repos/PowerShell/PowerShell/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\([^"]*\)".*/\1/p' | head -1)
  version="${version:-$PINNED_PWSH_VERSION}"
  url="https://github.com/PowerShell/PowerShell/releases/download/v$version/powershell-$version-$flavour.tar.gz"

  echo "  pwsh: not found — downloading PowerShell $version ($flavour) into the plugin's state..."
  dest="$state/pwsh-$version"
  tmp="$state/pwsh-download.tar.gz"
  rm -rf "$dest" "$tmp"
  if ! curl -fsSL --retry 3 --max-time 600 -o "$tmp" "$url"; then
    echo "  Download failed: $url" >&2
    echo "  Tried: an existing pwsh on PATH, a previous plugin copy, and this download." >&2
    echo "  This server needs outbound HTTPS to github.com (or an admin-installed pwsh 7.2+)." >&2
    rm -f "$tmp"
    exit 1
  fi
  mkdir -p "$dest" && tar -xzf "$tmp" -C "$dest" && rm -f "$tmp"
  chmod +x "$dest/pwsh"
  ln -sfn "$dest" "$state/pwsh"
  # Older unpacked versions are no longer referenced.
  for old in "$state"/pwsh-*; do
    [ -d "$old" ] && [ "$old" != "$dest" ] && rm -rf "$old"
  done
  if ! pwsh_ok "$state/pwsh/pwsh"; then
    echo "  The downloaded pwsh does not start. Output:" >&2
    "$state/pwsh/pwsh" -NoProfile -Command '$PSVersionTable' 2>&1 | sed 's/^/    /' >&2
    exit 1
  fi
  pwsh_bin="$state/pwsh/pwsh"
  echo "  pwsh: installed $version  ($pwsh_bin)"
fi
echo

# Record what run.sh / auth.sh need: PATH for pwsh, PSModulePath for the module.
{
  echo '# Written by install.sh, sourced by lib.sh before every command.'
  echo "export PATH=\"$(dirname "$pwsh_bin"):\$PATH\""
  echo "export PSModulePath=\"$modules\${PSModulePath:+:\$PSModulePath}\""
  [ -n "$icu_flag" ] && echo "$icu_flag"
} > "$state/env.sh"
[ -n "$icu_flag" ] && echo "  (libicu not found: PowerShell runs with invariant globalization.)"

echo "Installing the SqlServer module (Invoke-Sqlcmd) into the plugin's state..."
# Real HOME for the package cache would be nice but PowerShellGet keeps none worth
# sharing; the module itself goes to state/modules, outside any home.
export SQL_MODULES_DIR="$modules"
"$pwsh_bin" -NoLogo -NoProfile -NonInteractive -Command '
  $ErrorActionPreference = "Stop"
  $ProgressPreference = "SilentlyContinue"
  $dest = $env:SQL_MODULES_DIR
  $have = Get-ChildItem (Join-Path $dest "SqlServer") -Directory -ErrorAction SilentlyContinue |
          Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  try {
    if (Get-Command Save-PSResource -ErrorAction SilentlyContinue) {
      Save-PSResource -Name SqlServer -Path $dest -Repository PSGallery -TrustRepository -SkipDependencyCheck -Quiet
    } else {
      Save-Module -Name SqlServer -Path $dest -Repository PSGallery -Force
    }
  } catch {
    if ($have) {
      Write-Host "  Could not update the module ($($_.Exception.Message)); keeping SqlServer $($have.Name)."
    } else {
      [Console]::Error.WriteLine("  Could not download the SqlServer module from the PowerShell Gallery: $($_.Exception.Message)")
      [Console]::Error.WriteLine("  This server needs outbound HTTPS to www.powershellgallery.com.")
      exit 1
    }
  }
  # Keep only the newest version so Import-Module is unambiguous.
  $all = Get-ChildItem (Join-Path $dest "SqlServer") -Directory | Sort-Object { [version]$_.Name } -Descending
  $all | Select-Object -Skip 1 | Remove-Item -Recurse -Force
  $env:PSModulePath = "$dest" + [IO.Path]::PathSeparator + $env:PSModulePath
  Import-Module SqlServer -WarningAction SilentlyContinue
  $m = Get-Module SqlServer
  if (-not (Get-Command Invoke-Sqlcmd -Module SqlServer -ErrorAction SilentlyContinue)) { throw "Invoke-Sqlcmd not found after install." }
  if (-not (Get-Command Invoke-Sqlcmd).Parameters.ContainsKey("AccessToken")) { throw "This SqlServer version has no -AccessToken; Entra sign-in needs 21.1 or newer." }
  Write-Host "  SqlServer $($m.Version)  ($($m.ModuleBase))"
' || { echo "Install incomplete." >&2; exit 1; }

echo
echo "Ready."
echo
echo "Next, in the admin app:"
echo "  1. Settings — pick the sign-in mode and fill in its fields (tenant ID, client ID,"
echo "     username as needed), store the secret or password, and optionally a default"
echo "     server and database."
echo "  2. Authenticate — mints a token / connects with the stored credential and, when a"
echo "     default server is set, runs a test query to prove the database accepts it."
