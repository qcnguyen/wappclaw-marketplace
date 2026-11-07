# The human-facing half of auth-status: same checks, explained.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$mode = Get-SqlAuthMode
$problems = Get-SqlConfigProblems
if ($problems.Count -gt 0) { Write-SqlConfigProblems $problems; exit 2 }

Write-Host "Checking the Invoke-Sqlcmd credential."
Write-Host "  mode:     $mode"
if ($env:SQL_TENANT_ID -and $mode -in 'servicePrincipal', 'password') { Write-Host "  tenant:   $($env:SQL_TENANT_ID)" }
if ($env:SQL_CLIENT_ID) { Write-Host "  client:   $($env:SQL_CLIENT_ID)" }
if ($env:SQL_USERNAME -and $mode -in 'password', 'sqlLogin') { Write-Host "  username: $($env:SQL_USERNAME)" }
Write-Host "  server:   $(if ($env:SQL_SERVER) { $env:SQL_SERVER } else { '(no default server - only the sign-in can be checked)' })"
if ($env:SQL_DATABASE) { Write-Host "  database: $($env:SQL_DATABASE)" }
Write-Host "  applied:  $(if ($env:SQL_INJECT_AUTH -eq 'explicit') { 'only when a command references $SqlAccessToken / $SqlCredential' } else { 'automatically to every Invoke-Sqlcmd' })"
Write-Host ''

$params = @{ ConnectionTimeout = 15; QueryTimeout = 15 }
$step = 1
if (Test-SqlTokenMode $mode) {
    Write-Host "$step. Requesting an Azure SQL access token from Entra ID..."
    try { $token = Get-SqlAccessToken 25 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
    Write-Host '   Token issued.'
    $c = Get-SqlTokenClaims $token
    if ($c) {
        foreach ($k in 'upn', 'unique_name', 'appid', 'oid', 'tid') {
            if ($c.PSObject.Properties[$k]) { Write-Host ("   {0,-12} {1}" -f "${k}:", $c.$k) }
        }
        if ($c.PSObject.Properties['exp']) {
            Write-Host "   expires:     $([DateTimeOffset]::FromUnixTimeSeconds($c.exp).UtcDateTime.ToString('u')) (a fresh token is minted per command)"
        }
    }
    $params.AccessToken = $token
    $step++
    Write-Host ''
    if (-not $env:SQL_SERVER) {
        Write-Host "No default server is set, so SQL access could not be verified. The Entra credential itself is good."
        Write-Host "Set 'Default server' and run Authenticate again to check the database login too."
        exit 0
    }
} else {
    if (-not $env:SQL_SERVER) {
        [Console]::Error.WriteLine("SQL login mode can only be verified against a server. Set 'Default server' and run Authenticate again.")
        exit 1
    }
    $params.Credential = Get-SqlStoredCredential
}

$params.ServerInstance = $env:SQL_SERVER
if ($env:SQL_DATABASE) { $params.Database = $env:SQL_DATABASE }
$params.Query = 'SELECT SUSER_SNAME() AS login_name, USER_NAME() AS db_user, DB_NAME() AS db, @@VERSION AS version'

Write-Host "$step. Connecting to $($env:SQL_SERVER)..."
try {
    Import-SqlServerModule
    $r = Invoke-Sqlcmd @params
} catch {
    $msg = $_.Exception.Message
    [Console]::Error.WriteLine("   Connection failed: $msg")
    if ($msg -match 'Login failed|token-identified principal') {
        [Console]::Error.WriteLine('')
        [Console]::Error.WriteLine('   The credential is valid but SQL does not know this identity. In the target database, an admin runs:')
        [Console]::Error.WriteLine('     CREATE USER [<app or user name>] FROM EXTERNAL PROVIDER;')
        [Console]::Error.WriteLine('     ALTER ROLE db_datareader ADD MEMBER [<app or user name>];')
        [Console]::Error.WriteLine("   (For a SQL login, check the username/password and that the login is mapped to the database.)")
    } elseif ($msg -match 'certificate|SSL') {
        [Console]::Error.WriteLine('   The server certificate is not trusted (self-signed?). Commands can pass -TrustServerCertificate.')
    } elseif ($msg -match 'network-related|not found or was not accessible|timeout') {
        [Console]::Error.WriteLine('   Server unreachable. Check the name and that the Azure SQL firewall allows this machine''s IP.')
    }
    exit 1
}
Write-Host "   Connected."
Write-Host "   login:    $($r.login_name)"
Write-Host "   db user:  $($r.db_user)"
Write-Host "   database: $($r.db)"
Write-Host "   version:  $((($r.version -split "`n")[0]).Trim())"
Write-Host ''
Write-Host 'Signed in. Invoke-Sqlcmd commands now run through this plugin with this identity.'
