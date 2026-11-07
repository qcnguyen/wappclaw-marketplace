# Shared PowerShell for run.ps1, auth.ps1 and auth-status.ps1. Dot-sourced.
#
# Everything credential-shaped lives here: which mode is in force, whether it is
# configured, how an Entra access token for Azure SQL is minted, and how a SQL
# login becomes a PSCredential. Secrets are read from the environment (where the
# platform put them) and never written to disk, a command line, or the output.

Set-StrictMode -Version 3.0

# The Azure SQL resource. A token for `<this>/.default` is a token for any Azure
# SQL Database / Managed Instance / Synapse SQL endpoint in the tenant.
$script:SqlResource = 'https://database.windows.net'

# The Azure CLI's public client: a first-party, pre-consented app that may request
# Azure SQL tokens with a username + password. Used for password mode when no
# client ID of the organisation's own is configured.
$script:DefaultPublicClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'

function Get-SqlAuthMode {
    $mode = $env:SQL_AUTH_MODE
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'servicePrincipal' }
    return $mode
}

function Test-SqlTokenMode([string]$Mode) {
    return $Mode -in @('servicePrincipal', 'password', 'managedIdentity')
}

# Every missing field for the current mode at once, naming the admin field, so an
# admin fixes them in one visit. Returns an array of messages; empty = configured.
function Get-SqlConfigProblems {
    $mode = Get-SqlAuthMode
    $missing = @()
    switch ($mode) {
        'servicePrincipal' {
            if (-not $env:SQL_TENANT_ID)     { $missing += 'Entra tenant ID (SQL_TENANT_ID)' }
            if (-not $env:SQL_CLIENT_ID)     { $missing += 'Client ID (SQL_CLIENT_ID)' }
            if (-not $env:SQL_CLIENT_SECRET) { $missing += 'Service principal client secret (SQL_CLIENT_SECRET)' }
        }
        'password' {
            if (-not $env:SQL_TENANT_ID) { $missing += 'Entra tenant ID (SQL_TENANT_ID)' }
            if (-not $env:SQL_USERNAME)  { $missing += 'Username (SQL_USERNAME)' }
            if (-not $env:SQL_PASSWORD)  { $missing += 'Password (SQL_PASSWORD)' }
        }
        'managedIdentity' { }
        'sqlLogin' {
            if (-not $env:SQL_USERNAME) { $missing += 'Username (SQL_USERNAME)' }
            if (-not $env:SQL_PASSWORD) { $missing += 'Password (SQL_PASSWORD)' }
        }
        default { $missing += "Sign-in mode has an unknown value '$mode'" }
    }
    return , $missing
}

function Write-SqlConfigProblems([string[]]$Missing) {
    $mode = Get-SqlAuthMode
    [Console]::Error.WriteLine("This plugin is not configured for sign-in mode '$mode'. Missing:")
    foreach ($m in $Missing) { [Console]::Error.WriteLine("  - $m") }
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine("Set them in the admin app: Plugins -> $($env:PLUGIN_NAME) -> Settings.")
}

# Turn Entra's refusal into the thing to go and fix. The AADSTS code is the whole
# diagnosis, so it is quoted and then translated.
function Format-SqlTokenError([string]$Body) {
    $err = $null; $desc = $null
    try {
        $j = $Body | ConvertFrom-Json -ErrorAction Stop
        $err = $j.error; $desc = $j.error_description
    } catch { }
    $lines = @('Entra ID refused the sign-in.')
    if ($err)  { $lines += "  error:  $err" }
    if ($desc) { $lines += "  detail: $(($desc -split "`r?`n")[0])" }
    elseif ($Body) { $lines += "  raw: $($Body.Substring(0, [Math]::Min(400, $Body.Length)))" }
    $hint = switch -Regex ("$desc $Body") {
        'AADSTS7000215' { 'The client secret is wrong. Store the secret''s Value (shown once in Azure), not its Secret ID.'; break }
        'AADSTS7000222' { 'The client secret has EXPIRED. Create a new one under App registration -> Certificates & secrets.'; break }
        'AADSTS700016'  { 'No application with this client ID exists in this tenant. Check client ID and tenant ID come from the same directory.'; break }
        'AADSTS90002|AADSTS900023' { 'That tenant does not exist. Use the directory GUID or a verified domain.'; break }
        'AADSTS50126'   { 'Wrong username or password.'; break }
        'AADSTS50076|AADSTS50079|AADSTS50158' { 'This account requires MFA / conditional access, which a password sign-in cannot satisfy. Use a service principal or an account excluded from MFA.'; break }
        'AADSTS50034'   { 'That user does not exist in this tenant.'; break }
        'AADSTS50053'   { 'The account is locked (too many failed sign-ins).'; break }
        'AADSTS50055'   { 'The password has expired.'; break }
        'AADSTS65001'   { 'The client app has not been consented for Azure SQL in this tenant.'; break }
        default         { 'Search the AADSTS number above — Microsoft documents each one.' }
    }
    $lines += "  meaning: $hint"
    return ($lines -join [Environment]::NewLine)
}

function Invoke-SqlTokenRequest([string]$Uri, [hashtable]$Body, [int]$TimeoutSec) {
    try {
        $r = Invoke-RestMethod -Method Post -Uri $Uri -Body $Body -TimeoutSec $TimeoutSec `
            -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        return $r.access_token
    } catch {
        $response = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $response = $_.ErrorDetails.Message }
        if ($response) { throw (Format-SqlTokenError $response) }
        throw "Could not reach the Entra token endpoint: $($_.Exception.Message)"
    }
}

# Mint an Azure SQL access token for the configured mode. Returns the token string.
# Throws a human-readable message on failure.
function Get-SqlAccessToken([int]$TimeoutSec = 25) {
    $mode = Get-SqlAuthMode
    switch ($mode) {
        'servicePrincipal' {
            return Invoke-SqlTokenRequest "https://login.microsoftonline.com/$($env:SQL_TENANT_ID)/oauth2/v2.0/token" @{
                grant_type    = 'client_credentials'
                client_id     = $env:SQL_CLIENT_ID
                client_secret = $env:SQL_CLIENT_SECRET
                scope         = "$script:SqlResource/.default"
            } $TimeoutSec
        }
        'password' {
            $clientId = if ($env:SQL_CLIENT_ID) { $env:SQL_CLIENT_ID } else { $script:DefaultPublicClientId }
            return Invoke-SqlTokenRequest "https://login.microsoftonline.com/$($env:SQL_TENANT_ID)/oauth2/v2.0/token" @{
                grant_type = 'password'
                client_id  = $clientId
                username   = $env:SQL_USERNAME
                password   = $env:SQL_PASSWORD
                scope      = "$script:SqlResource/.default openid"
            } $TimeoutSec
        }
        'managedIdentity' {
            # App Service / Functions / Container Apps expose IDENTITY_ENDPOINT; a VM
            # or VMSS has IMDS at the link-local address.
            try {
                if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
                    $uri = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$([uri]::EscapeDataString($script:SqlResource + '/'))"
                    if ($env:SQL_CLIENT_ID) { $uri += "&client_id=$($env:SQL_CLIENT_ID)" }
                    $r = Invoke-RestMethod -Uri $uri -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER } -TimeoutSec $TimeoutSec -ErrorAction Stop
                } else {
                    $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$([uri]::EscapeDataString($script:SqlResource + '/'))"
                    if ($env:SQL_CLIENT_ID) { $uri += "&client_id=$($env:SQL_CLIENT_ID)" }
                    $r = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -NoProxy -TimeoutSec $TimeoutSec -ErrorAction Stop
                }
                return $r.access_token
            } catch {
                $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
                throw "Could not get a managed identity token: $detail`n  This mode only works on an Azure VM / App Service with a managed identity assigned. For a user-assigned identity, set 'Client ID' to its client ID."
            }
        }
        default { throw "Sign-in mode '$mode' does not use an access token." }
    }
}

function Get-SqlStoredCredential {
    $secure = ConvertTo-SecureString -String $env:SQL_PASSWORD -AsPlainText -Force
    return [pscredential]::new($env:SQL_USERNAME, $secure)
}

# Remove the long-lived secrets from this process's environment before any
# user-supplied code runs: the command needs a one-hour token, not the secret
# that mints it. ($SqlCredential, when used, carries the SQL login's password
# in-process; that is inherent to SQL authentication.)
function Clear-SqlSecretEnvironment {
    Remove-Item Env:SQL_CLIENT_SECRET -ErrorAction SilentlyContinue
    Remove-Item Env:SQL_PASSWORD -ErrorAction SilentlyContinue
}

function Import-SqlServerModule {
    try {
        Import-Module SqlServer -ErrorAction Stop -WarningAction SilentlyContinue
    } catch {
        throw "The SqlServer PowerShell module is not available ($($_.Exception.Message)). An administrator needs to press Install (or Reinstall) on the '$($env:PLUGIN_NAME)' plugin."
    }
}

# Decode a JWT's payload (base64url — encoding, not encryption) to show *who* a
# token is for. Never used to print the token itself.
function Get-SqlTokenClaims([string]$Token) {
    try {
        $p = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
    } catch { return $null }
}
