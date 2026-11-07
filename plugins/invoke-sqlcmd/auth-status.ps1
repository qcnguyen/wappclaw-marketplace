# Is the stored credential actually usable? Exit 0 = yes.
#
# It really signs in rather than checking that a secret is *present*: an expired
# client secret or changed password is the commonest failure, and a probe that
# only looked for a stored value would show green through the whole outage.
#
#  - Entra modes: a token must be issued; and when a default server is set, a
#    `SELECT 1` with that token must succeed (the identity also has to exist as a
#    database user, which Entra alone cannot tell us).
#  - SQL login: there is nothing to ask without a server, so a default server is
#    required for a "yes".
#
# Budget: the platform caps this at 20 s, so every call here is short-timeout.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

if ((Get-SqlConfigProblems).Count -gt 0) { exit 1 }
$mode = Get-SqlAuthMode

$params = @{ Query = 'SELECT 1 AS ok'; ConnectionTimeout = 8; QueryTimeout = 5 }
if (Test-SqlTokenMode $mode) {
    try { $params.AccessToken = Get-SqlAccessToken 6 } catch { exit 1 }
    if (-not $params.AccessToken) { exit 1 }
    if (-not $env:SQL_SERVER) { exit 0 }
} else {
    if (-not $env:SQL_SERVER) { exit 1 }
    $params.Credential = Get-SqlStoredCredential
}
$params.ServerInstance = $env:SQL_SERVER
if ($env:SQL_DATABASE) { $params.Database = $env:SQL_DATABASE }

try {
    Import-SqlServerModule
    $r = Invoke-Sqlcmd @params
    if ($r -and $r.ok -eq 1) { exit 0 }
} catch { }
exit 1
