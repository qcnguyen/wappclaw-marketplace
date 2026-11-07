# Validate and run one Invoke-Sqlcmd command. Invoked by run.sh, which has already
# checked the `Invoke-Sqlcmd` prefix; the command arrives in $env:PLUGIN_COMMAND.
#
# Two jobs:
#
#  1. **The gate.** The prefix check in run.sh is a string test, which
#     `Invoke-Sqlcmd -Query 'x'; Remove-Item ...` passes. So the command is parsed
#     here and its syntax tree checked: one pipeline, headed by Invoke-Sqlcmd,
#     optionally piped into a short list of formatting cmdlets — and no other
#     command, method call or script invocation anywhere inside it.
#
#  2. **The credential.** The command is run *as written*. Nothing is spliced into
#     its text; instead the stored credential is applied the way PowerShell itself
#     offers — $PSDefaultParameterValues, which fills a parameter only when the
#     command did not pass one. A command that brings its own -AccessToken,
#     -Credential, -Username/-Password or -ConnectionString is left alone. The same
#     credential is also exposed as $SqlAccessToken / $SqlCredential for commands
#     that want to pass it explicitly, as an ordinary script would.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

function Fail([string]$Message, [int]$Code = 1) {
    [Console]::Error.WriteLine($Message)
    exit $Code
}

$commandText = $env:PLUGIN_COMMAND
Remove-Item Env:PLUGIN_COMMAND -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# 1. The gate
# ---------------------------------------------------------------------------

$parseTokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($commandText, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $msg = "The command is not valid PowerShell:"
    foreach ($e in $parseErrors) { $msg += "`n  line $($e.Extent.StartLineNumber), col $($e.Extent.StartColumnNumber): $($e.Message)" }
    Fail $msg 2
}

$reject = {
    param([string]$Why)
    Fail ("Rejected: $Why`n`nThis plugin runs a single Invoke-Sqlcmd command, optionally piped into a formatting cmdlet " +
          "($(($script:AllowedDownstream | Sort-Object) -join ', ')). Put all SQL logic in the -Query text or an -InputFile.") 2
}

# Formatting / shaping cmdlets that may follow Invoke-Sqlcmd in the pipeline.
# ForEach-Object and anything that runs arbitrary code are deliberately absent.
$script:AllowedDownstream = @(
    'Select-Object', 'Where-Object', 'Sort-Object', 'Group-Object', 'Measure-Object',
    'Format-Table', 'Format-List', 'Format-Wide', 'Out-String',
    'ConvertTo-Json', 'ConvertTo-Csv', 'ConvertTo-Html', 'ConvertTo-Xml', 'Export-Csv',
    'select', 'where', 'sort', 'group', 'measure', 'ft', 'fl'
)

if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $ast.DynamicParamBlock) {
    & $reject 'param/begin/process blocks are not allowed.'
}
$statements = @($ast.EndBlock.Statements)
if ($statements.Count -ne 1) {
    & $reject "expected exactly one statement, found $($statements.Count) (';', newlines between commands, '&&' and '||' are not allowed)."
}
$pipeline = $statements[0]
if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) {
    & $reject 'the command must be a plain Invoke-Sqlcmd pipeline (no assignments, if/foreach, functions or && / || chains).'
}
if ($pipeline.Background) { & $reject "background jobs ('&' at the end) are not allowed." }

$elements = @($pipeline.PipelineElements)
$head = $elements[0]
if ($head -isnot [System.Management.Automation.Language.CommandAst] -or
    $head.InvocationOperator -ne 'Unknown' -or
    $head.GetCommandName() -ne 'Invoke-Sqlcmd') {
    & $reject 'the command must start with Invoke-Sqlcmd.'
}
for ($i = 1; $i -lt $elements.Count; $i++) {
    $el = $elements[$i]
    $name = if ($el -is [System.Management.Automation.Language.CommandAst]) { $el.GetCommandName() } else { $null }
    if (-not $name -or $el.InvocationOperator -ne 'Unknown' -or $script:AllowedDownstream -notcontains $name) {
        & $reject "'$($el.Extent.Text)' cannot follow Invoke-Sqlcmd in the pipeline."
    }
}

# Nothing else may execute: no command hidden in $( ), a script block or an
# argument, and no .NET method call ([IO.File]::Delete(...), $x.Invoke(...)).
$topLevel = [System.Collections.Generic.HashSet[object]]::new()
foreach ($el in $elements) { [void]$topLevel.Add($el) }
$nested = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
    Where-Object { -not $topLevel.Contains($_) }
foreach ($n in @($nested)) {
    $hint = ''
    if ($n.Parent -and $n.Parent.Parent -is [System.Management.Automation.Language.SubExpressionAst]) {
        $hint = " If this is a sqlcmd variable like `$(MyVar), put the query in single quotes so PowerShell does not expand it."
    }
    & $reject "'$($n.Extent.Text)' is a nested command.$hint"
}
$methodCalls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)
foreach ($m in @($methodCalls)) { & $reject "method calls such as '$($m.Extent.Text)' are not allowed." }

# ---------------------------------------------------------------------------
# 2. The credential
# ---------------------------------------------------------------------------

$authParams = @('AccessToken', 'Credential', 'Username', 'Password', 'ConnectionString')
$given = @($head.CommandElements |
    Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
    ForEach-Object { $_.ParameterName })
# PowerShell accepts unambiguous prefixes (-Cred, -User), so match those too.
$userAuth = [bool]($given | Where-Object { $p = $_; $authParams | Where-Object { $_ -like "$p*" } })
$usesConnectionString = [bool]($given | Where-Object { 'ConnectionString' -like "$_*" -and $_.Length -ge 3 })

$varNames = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
    ForEach-Object { $_.VariablePath.UserPath })
$usesTokenVar = [bool]($varNames | Where-Object { $_ -eq 'SqlAccessToken' })
$usesCredVar  = [bool]($varNames | Where-Object { $_ -eq 'SqlCredential' })

$mode = Get-SqlAuthMode
$inject = if ($env:SQL_INJECT_AUTH -eq 'explicit') { 'explicit' } else { 'auto' }
$autoApply = ($inject -eq 'auto') -and -not $userAuth

if ($usesTokenVar -and -not (Test-SqlTokenMode $mode)) {
    Fail "`$SqlAccessToken is only available in the Entra ID sign-in modes; this plugin is set to '$mode'. Use `$SqlCredential instead." 2
}
if ($usesCredVar -and $mode -ne 'sqlLogin') {
    Fail "`$SqlCredential is only available in the 'sqlLogin' sign-in mode; this plugin is set to '$mode'. Use `$SqlAccessToken instead." 2
}

$SqlAccessToken = $null
$SqlCredential = $null
if ($autoApply -or $usesTokenVar -or $usesCredVar) {
    $problems = Get-SqlConfigProblems
    if ($problems.Count -gt 0) { Write-SqlConfigProblems $problems; exit 2 }

    if (Test-SqlTokenMode $mode) {
        # A token per command: valid for about an hour, never written to disk, so a
        # rotated secret takes effect on the very next command.
        try { $SqlAccessToken = Get-SqlAccessToken 25 } catch { Fail $_.Exception.Message 1 }
    } else {
        $SqlCredential = Get-SqlStoredCredential
    }
}
Clear-SqlSecretEnvironment

$PSDefaultParameterValues = @{}
if ($autoApply) {
    if ($SqlAccessToken) { $PSDefaultParameterValues['Invoke-Sqlcmd:AccessToken'] = $SqlAccessToken }
    if ($SqlCredential)  { $PSDefaultParameterValues['Invoke-Sqlcmd:Credential']  = $SqlCredential }
}
# A connection string carries its own server and database, and is a different
# parameter set — defaults for those would make the call ambiguous.
if (-not $usesConnectionString) {
    if ($env:SQL_SERVER)   { $PSDefaultParameterValues['Invoke-Sqlcmd:ServerInstance'] = $env:SQL_SERVER }
    if ($env:SQL_DATABASE) { $PSDefaultParameterValues['Invoke-Sqlcmd:Database']       = $env:SQL_DATABASE }
}

try { Import-SqlServerModule } catch { Fail $_.Exception.Message 1 }

# Dot-sourced so the command sees $PSDefaultParameterValues, $SqlAccessToken and
# $SqlCredential from this scope.
$block = [scriptblock]::Create($commandText)
try {
    . $block
} catch {
    $msg = $_.Exception.Message
    if ($msg -match 'Login failed for user|token-identified principal') {
        $msg += "`n`nSigned in to Entra ID, but SQL refused the identity. It must exist as a user in the target database " +
                "(CREATE USER [<name>] FROM EXTERNAL PROVIDER) — ask a database administrator."
    } elseif ($msg -match 'certificate chain|not trusted|SSL Provider') {
        $msg += "`n`nThe server's TLS certificate is not trusted. For a server with a self-signed certificate add -TrustServerCertificate."
    }
    Fail $msg 1
}
