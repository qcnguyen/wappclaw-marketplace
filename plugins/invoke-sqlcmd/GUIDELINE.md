# SQL Server / Azure SQL, through Invoke-Sqlcmd

This plugin runs PowerShell's **`Invoke-Sqlcmd`** (SqlServer module) with a stored
credential already in place. Write the command exactly as you would in PowerShell:

```powershell
Invoke-Sqlcmd -ServerInstance myserver.database.windows.net -Database mydb -Query 'SELECT TOP 10 name, create_date FROM sys.tables ORDER BY create_date DESC'
```

**Every command must begin with `Invoke-Sqlcmd`.** Anything else is rejected before it
runs — no other cmdlets, no `;`, `&&` or a second line, no `$( … )` subexpressions, no
method calls. The only thing allowed after it is a pipe into a formatting cmdlet:
`Select-Object`, `Where-Object`, `Sort-Object`, `Group-Object`, `Measure-Object`,
`Format-Table`, `Format-List`, `Format-Wide`, `Out-String`, `ConvertTo-Json`,
`ConvertTo-Csv`, `ConvertTo-Html`, `ConvertTo-Xml`, `Export-Csv`. Put the logic in SQL.

The same command in a plain shell has no credential and no `Invoke-Sqlcmd` — use this plugin.

## Signing in — you usually do nothing

An administrator stores one credential for the plugin (Entra ID service principal,
Entra user + password, managed identity, or a SQL login). By default it is applied to
every `Invoke-Sqlcmd` automatically, so **do not add `-AccessToken`, `-Credential`,
`-Username` or `-Password`**.

If a default server/database is configured, `-ServerInstance` / `-Database` can be
left off too; passing them always wins.

### Using the stored credential explicitly

The credential is also available as variables, for when you want to pass it yourself,
exactly as an ordinary script would (and required if the admin set the plugin to
*only when the command references it*):

| Variable | Sign-in modes | Use as |
|---|---|---|
| `$SqlAccessToken` | service principal, Entra user, managed identity | `-AccessToken $SqlAccessToken` |
| `$SqlCredential` | SQL login | `-Credential $SqlCredential` |

```powershell
Invoke-Sqlcmd -ServerInstance myserver.database.windows.net -Database mydb -AccessToken $SqlAccessToken -Query 'SELECT SUSER_SNAME()'
```

### Bringing your own credential

A command that passes its own `-AccessToken`, `-Credential`, `-Username`/`-Password` or
`-ConnectionString` is left alone — nothing stored is applied to it:

```powershell
Invoke-Sqlcmd -ConnectionString 'Server=tcp:other.database.windows.net;Database=x;Authentication=Active Directory Default' -Query 'SELECT 1'
```

## Commands

| Task | Command |
|---|---|
| Who am I / where am I | `Invoke-Sqlcmd -Query 'SELECT SUSER_SNAME() AS login, DB_NAME() AS db, @@VERSION AS version'` |
| List databases | `Invoke-Sqlcmd -Database master -Query 'SELECT name, state_desc FROM sys.databases'` |
| List tables | `Invoke-Sqlcmd -Query 'SELECT s.name AS [schema], t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id ORDER BY 1,2'` |
| Columns of a table | `Invoke-Sqlcmd -Query "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Orders'"` |
| Run a .sql file | `Invoke-Sqlcmd -InputFile ./migration.sql` |
| sqlcmd variables | `Invoke-Sqlcmd -Query 'SELECT * FROM t WHERE id = $(Id)' -Variable 'Id=42'` |
| Long query | add `-QueryTimeout 600` (seconds; default 30) |
| PRINT / RAISERROR output | add `-Verbose` |
| JSON out | `Invoke-Sqlcmd -Query '…' \| Select-Object * -ExcludeProperty RowError,RowState,Table,ItemArray,HasErrors \| ConvertTo-Json` |
| CSV file | `Invoke-Sqlcmd -Query '…' \| Export-Csv ./result.csv -NoTypeInformation` |
| Wide table, untruncated | `Invoke-Sqlcmd -Query '…' \| Format-Table -AutoSize \| Out-String -Width 4096` |

`Get-Help Invoke-Sqlcmd` is not runnable here; the parameters are documented at
learn.microsoft.com/powershell/module/sqlserver/invoke-sqlcmd.

## Traps

- **Quote queries with single quotes.** In double quotes PowerShell expands `$(Name)` and
  `$var` before SQL sees it — a sqlcmd variable like `$(Id)` becomes a command and is
  rejected. Inside single quotes, double a literal `'` as `''`.
- **Results are DataRows.** Default output is a table that truncates wide columns; pipe
  to `Format-List` or `ConvertTo-Json` for full values. `ConvertTo-Json` without the
  `Select-Object -ExcludeProperty …` above includes DataRow plumbing.
- **Large results:** always `SELECT TOP (n)` or filter in SQL; don't fetch whole tables.
- **Encryption is mandatory by default** (SqlServer 22+). A server with a self-signed
  certificate needs `-TrustServerCertificate`. Azure SQL does not.
- **One batch per `-Query` is not required** — `GO` separators work, as in sqlcmd.
- **Writes are real.** `INSERT`/`UPDATE`/`DELETE`/DDL run immediately with no
  confirmation. Confirm with the user before changing data or schema, and prefer a
  `SELECT` that shows what would change first.

## What failure means

- **"This plugin is not configured…"** or **"Entra ID refused the sign-in"** (with an
  AADSTS code) — the stored credential is missing, wrong or expired. You cannot fix it;
  an administrator updates it in the admin app (Plugins → invoke-sqlcmd → Settings)
  and presses Authenticate.
- **"Login failed for user '<token-identified principal>'"** — the credential is valid
  but that identity is not a user in this database. A DBA must run
  `CREATE USER [<name>] FROM EXTERNAL PROVIDER` and grant a role.
- **"The server was not found or was not accessible"** — wrong server name, or the Azure
  SQL firewall does not allow this machine.
- **Permission denied on an object** — signed in fine, just not granted. Report it; the
  identity's permissions are the plugin's permissions.

**Whose account this is.** Everything runs as the identity an administrator configured,
so what you can see and change is what that identity was granted — "invalid object
name" may mean "not visible to it".
