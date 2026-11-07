# SheetyApp (`shp` CLI)

This plugin gives you **`shp`**, the SheetyApp command-line tool, installed and signed in. With it you read workbook structure, answer questions about workbooks, and make changes in them on the user's behalf. Every command starts with `shp`; run `shp --help` or `shp <group> <command> --help` for the exact options of the installed version — the help is authoritative where it differs from this document.

It is self-contained for everyday work. For full reference detail, read the companion docs in the `reference/` folder next to this file:

| Doc | Read it for |
|-----|-------------|
| [sheetyapp-introduction.md](reference/sheetyapp-introduction.md) | Product overview, workbook snapshot structure |
| [sheetyapp-q-expression.md](reference/sheetyapp-q-expression.md) | Complete Q-Expression reference |
| [sheetyapp-q-text.md](reference/sheetyapp-q-text.md) | Complete Q-Text reference |
| [sheetyapp-row-action.md](reference/sheetyapp-row-action.md) | Row-actions, triggers, fire conditions, timing actions, procedures, webhooks |
| [sheetyapp-row-action-yaml-instruction.md](reference/sheetyapp-row-action-yaml-instruction.md) | Every YAML instruction with parameters and examples |
| [sheetyapp-sitemap.md](reference/sheetyapp-sitemap.md) | Web app routes, for giving users page links |

---

## 1. Role and Working Style

- Help users understand their workbook and accomplish their goals in it. When asked to do something, plan the steps, run them, and check the result.
- **Know the workbook before acting.** Inspect sheets, columns and existing automations first; never guess sheet IDs, nameIds, column nameIds or option IDs.
- **Confirm before destructive changes** (deleting sheets, columns, rows, queries, workflows or workbooks), unless the user has explicitly asked for that exact deletion.
- **Keep replies concise** and formatted as markdown: bullet points for lists, markdown links (`[Orders sheet](https://go.sheetyapp.com/workbooks/...)`) when pointing to pages.
- Don't expose internal implementation details (API endpoints, internal tool names) unless the user is a developer asking about them.
- When something can't be done through `shp`, say so and link the user to the right page in the web app (see [Web App Links](#9-web-app-links)).

### SheetyApp Vocabulary

These words have specific meanings in SheetyApp. Use the companion docs when a request involving them is ambiguous.

| Term | Meaning |
|------|---------|
| **Workbook** | A container of sheets, automations and apps, shared by its members |
| **Sheet** | A data table with typed columns and rows |
| **Q-Expression** | The formula language for computed columns, filters, rules and workflow logic |
| **Q-Predicate** | A Q-Expression that returns true/false (filters, conditions) |
| **Q-Function** (or "Function") | A custom JavaScript function callable from Q-Expressions |
| **Lookup expression** | Q-Expression syntax for reading a value from another sheet: `$value:sheet@matchColumn:selectColumn` |
| **Query** (Query View, Sheet Query) | A saved filter + column selection over one sheet |
| **App** (Workbook App) | A dashboard of widgets (grids, charts, Gantt, Q-Text…) |
| **Row-Action** | A workflow attached to a sheet, triggered by row create/update/delete or run on demand |
| **YAML instructions** | The language workflows are written in |
| **Timing Action** | A workflow run on a cron schedule or at dates taken from a query |
| **Procedure** | A reusable workflow with parameters, called by other workflows |
| **Webhook** | A workflow started by an external HTTP call |
| **Q-Text** | Templating language (Liquid + `{% q %}`) for messages, URLs and payloads |
| **Field** (Workbook Field) | A single workbook-level value, read as `$_f_<nameId>` |
| **Sheet Association** | A computed summary, shown on a row, of rows in another sheet that reference it |

---

## 2. Access: Whose Account, and What It Can Reach

### The signed-in account
- Every command runs as **the SheetyApp account an administrator signed this plugin in with** (admin app → Plugins → sheetyapp → Authenticate). It is not necessarily the person you are chatting with.
- `shp auth status` (or `--json`) shows which account that is.
- **You cannot sign in or out.** `shp auth login` and `shp auth logout` are refused. If commands fail with `Session expired` or `Not logged in`, tell the user an administrator has to Authenticate the plugin again.
- The login belongs to this plugin: a `shp` run from a plain shell is a different, signed-out CLI. Always use the plugin.

### Delegation (required per workbook)
The CLI signs in as the client `cli` and can **only access workbooks delegated to it**. The signed-in account grants this in the web app: workbook **Settings → Connected Apps** (`$SHEETYAPP_WEB_URL/workbooks/<workbookId>/settings#connected-apps`), choosing a role for the CLI.

- The CLI acts with the **delegated role, capped by the account's own membership role**.
- `shp workbook list` shows only delegated workbooks. "Not found" or a missing workbook usually means **not delegated**, not "doesn't exist".
- A `Permission denied` error means the workbook isn't delegated, or the delegated role is too low for the action. Ask the user to delegate it (or raise the role), and give them the link.
- While acting through the CLI, `$ActingMember.ClientId` is `'cli'` in Q-Expressions, so workbook rules can tell CLI changes apart from web/mobile changes.

### What failure means
| Output | Meaning | What to do |
|--------|---------|-----------|
| `Session expired` / `Not logged in` | The plugin's sign-in is gone | Ask an administrator to Authenticate the plugin |
| `Permission denied. The CLI acts with the role you delegated…` | Workbook not delegated, or role too low | Ask the user to delegate / raise the role (Connected Apps link) |
| `Cannot connect to API at …` | Network, or the plugin's API URL setting | Report it; you cannot change settings |
| `No workbook specified` | No `--workbook` and no default | `shp workbook use <id>` or pass `--workbook` |
| `Unknown command '<group>'` or an unknown option (e.g. `webhook`, `field`, `--fire-field`) | The installed `shp` is older than this guide | Ask an administrator to Reinstall the plugin |
| Any other message | The API's validation message | Read it, fix the input; don't retry unchanged |

### Roles and What They Allow

| Role | Read data | Write rows | Design (sheets, columns, queries, workflows) | Manage members |
|------|-----------|-----------|---------------------------------------------|----------------|
| Owner | ✓ | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | ✓ | ✓ |
| Contributor | ✓ | ✓ | ✓ | |
| SheetWriter | ✓ | ✓ | | |
| SheetReader | ✓ | | | |

### Selecting a Workbook
```bash
shp workbook list                 # accessible workbooks and their IDs
shp workbook use <workbookId>     # set the default for later commands
shp sheet list --workbook <id>    # or pass --workbook on any command
```

The default set by `shp workbook use` is stored in the plugin's own config, so it **persists across conversations and is shared by everyone using the plugin**. Prefer passing `--workbook <id>` on every command; if you do rely on the default, confirm it first (`shp workbook list` marks it) rather than assuming the one from an earlier chat.

---

## 3. CLI Conventions

- **IDs**: `workbookId` is a hash-id string; `sheetId` is the sheet's **numeric** ID; columns are addressed by **column nameId**; rows by numeric row ID; queries, row-actions, procedures, timing actions and executions by GUID.
- **`--json`**: most read commands accept `--json` for machine-readable output. Prefer it when you need to parse results.
- **JSON inputs** (`--values`, `--spec`, `--params`, `--params-def`): pass inline JSON or a path to a JSON file.
- **YAML inputs** (`--yaml`): a file path, or `-` to read from stdin.
- **`--force`**: skips confirmation on deletes. The CLI is non-interactive in agent shells, so deletes require `--force` — only add it after the user has confirmed.
- **Errors**: the CLI prints the API's error message; read it and fix the input rather than retrying unchanged.
- **Files**: relative paths (`-o wb.json`, `--yaml action.yaml`, `--values rows.json`) resolve in the command's working directory — your scratch folder unless you name another. Write YAML and JSON inputs there first, then pass the path.
- **No prompts**: nothing can answer an interactive prompt. Every command that would ask has a flag instead (`--force` for deletes).

---

## 4. Understanding a Workbook

Start every non-trivial task by learning the workbook's structure.

```bash
shp workbook export -o wb.json                  # full definition snapshot (no rows); prints JSON to stdout without -o
shp workbook export --include-rows -o wb.json   # snapshot including row data
shp sheet list --json
shp sheet get <sheetId> --json
shp column list <sheetId> --json                # column nameIds, types, select option IDs
shp query list --json
shp row-action list --sheet <sheetId> --json
shp procedure list --json
shp timing-action list --json
shp association list <sheetId> --json
```

`workbook export` needs a design-capable role (Owner, Admin, Contributor). With a lower role, use `sheet list`, `sheet get`, `column list` and `query list` instead.

The export snapshot holds sheets, columns, queries, q-functions, fields, API templates, secret metadata, row-actions, timing actions, procedures, webhooks, row triggers and apps — see [sheetyapp-introduction.md](reference/sheetyapp-introduction.md) for its structure.

**How to analyze a workbook:**
1. Identify the core sheets and how they relate (RowRef columns, sheet associations, lookups)
2. Read column types, computed columns and validation rules to understand the data model
3. Read q-functions for shared calculations
4. Read row-actions, timing actions, procedures and webhooks for the business processes
5. Check API templates and secrets for external integrations
6. Look at queries and apps for reporting needs

---

## 5. CLI Command Reference

### Workbooks
| Command | Purpose |
|---------|---------|
| `shp workbook list [--json]` | List accessible workbooks |
| `shp workbook use <workbookId>` | Set the default workbook |
| `shp workbook create --name <n> [--description <d>] [--timezone <IANA>]` | Create a workbook |
| `shp workbook update [--name] [--description] [--timezone]` | Rename or change description/timezone |
| `shp workbook clone [--name] [--description] [--include-rows]` | Copy a workbook |
| `shp workbook export [--include-rows] [-o <file>]` | Export the definition snapshot as JSON |
| `shp workbook import <file> [--name] [--description]` | Create a **new** workbook from an exported snapshot |
| `shp workbook delete <workbookId> [--force]` | Delete a workbook |

### Sheets and Columns
| Command | Purpose |
|---------|---------|
| `shp sheet list [--json]` | List sheets |
| `shp sheet get <sheetId> [--json]` | Sheet details |
| `shp sheet create --name <n> [--description <d>]` | Create a sheet |
| `shp sheet clone <sheetId> [--name] [--description]` | Copy a sheet's structure |
| `shp sheet update <sheetId> [--name] [--description] [--restriction '<pred>' \| --no-restriction] [--representative-column <col>] [--submenu \| --no-submenu]` | Rename a sheet or change its settings; `--restriction` is the row restriction (`allowRowManipulationQExpression`), checked as a boolean Q-Expression first |
| `shp sheet delete <sheetId> [--force]` | Delete a sheet |
| `shp column list <sheetId> [--json]` | List columns |
| `shp column create <sheetId> --name <n> --type <type> [options]` | Add a column |
| `shp column update <sheetId> <columnNameId> [options]` | Change a column (unspecified settings are kept) |
| `shp column clone <sheetId> <columnNameId> [--flatten]` | Duplicate a column; `--flatten` turns a Compute column into a plain column holding its current values |
| `shp column delete <sheetId> <columnNameId> [--force]` | Delete a column |

Column options:
- `--type`: `Number`, `Boolean`, `String`, `DateTime`, `Compute`, `SingleSelect`, `MultiSelect`, `RowRef`, `MultiRowRef`, `Member`, `SealedSingleSelect`, `SingleVote`
- `--expr "<Q-Expression>"`: formula of a Compute column (implies `--type Compute`)
- `--ref-sheet <sheetId>`: target sheet of a RowRef / MultiRowRef column
- `--options "A,B,C"`: option labels of select/vote columns. On update, existing labels keep their option IDs, so existing row values stay valid
- `--allow-edit "<Q-Expression>"`: rule deciding whether a cell is editable
- `--description <text>`
- `--spec <json>`: full column definition for anything else (e.g. `validationRules`, `fieldSuggestionConfig`, `textDisplayVariant`)

```bash
shp column create 3 --name "Status" --type SingleSelect --options "Open,In Progress,Done"
shp column create 3 --name "Line Total" --expr "@quantity * @unitPrice"
shp column create 3 --name "Customer" --type RowRef --ref-sheet 2
```

### Unique Constraints
| Command | Purpose |
|---------|---------|
| `shp unique-constraint list <sheetId> [--json]` | List a sheet's unique constraints |
| `shp unique-constraint create <sheetId> --columns a,b` | No two rows may share the same values in these columns (together) |
| `shp unique-constraint delete <sheetId> <constraintId> [--force]` | Delete one |

- Compute, MultiSelect and SingleVote columns can't be part of a constraint.
- Creating one **fails if existing rows already collide** — find and fix duplicates first (`shp row search`). Afterwards, a write that would duplicate is rejected (and a workflow write is silently not saved).
- A lookup's match column must be unique; a constraint on it guarantees that.

### Rows
| Command | Purpose |
|---------|---------|
| `shp row list <sheetId> [--row-ids 1,2] [--json]` | List rows (or specific rows) |
| `shp row search <sheetId> --expr "<Q-Predicate>" [--json]` | Find rows matching a Q-Expression |
| `shp row create <sheetId> --values <json>` | Create a row |
| `shp row bulk-create <sheetId> --values <json-array>` | Create many rows |
| `shp row update <sheetId> <rowId> --values <json>` | Patch only the given columns |
| `shp row delete <sheetId> <rowIds> [--force]` | Delete rows (comma-separated IDs) |

`--unlock-restriction` on create/update/delete bypasses the sheet's row restriction. It requires a design-capable role; only use it when the user asks.

**Row values** are a JSON object keyed by **column nameId**. Each value must match the column type:

| Column type | Value |
|-------------|-------|
| Number | number |
| Boolean | `true` / `false` |
| String | text |
| DateTime | ISO 8601 text, e.g. `"2025-04-12T09:00:00Z"` |
| SingleSelect, SealedSingleSelect, SingleVote | the **option ID** (not the label) |
| MultiSelect | array of option IDs |
| RowRef | numeric row ID of the referenced row |
| MultiRowRef | array of row IDs |
| Member | the member's IdP subject (IdpSub) |
| Compute | not settable — computed |

Get option IDs from `shp column list <sheetId> --json` (`selectOptions` maps option ID → label).

```bash
shp row create 3 --values '{"title":"Fix login","status":"5b0c…-option-id","assignee":"<idpSub>","customer":42}'
shp row update 3 1017 --values '{"status":"9e2a…-option-id"}'
```

### Queries
| Command | Purpose |
|---------|---------|
| `shp query list / get <id>` | List or show queries |
| `shp query run <id> [--limit n] [--json]` | Run a query and show its rows |
| `shp query create --sheet <sheetId> --name <n> [--filter <pred>] [--columns a,b] [--compute "Name=<expr>"]...` | Create a query |
| `shp query update <id> [same options]` | Change a query (`--compute` replaces all computed columns) |
| `shp query delete <id> [--force]` | Delete a query |

### Sheet Associations
| Command | Purpose |
|---------|---------|
| `shp association list <sheetId>` | List associations of a sheet |
| `shp association rows <sheetId> <associationId> --row <rowId>` | Show rows associated with a row |
| `shp association update <sheetId> <associationId> [--name] [--eval-text <Q-Text>] [--active/--inactive]` | Change an association |

### Row-Actions
| Command | Purpose |
|---------|---------|
| `shp row-action list [--sheet <sheetId>]` | List row-actions |
| `shp row-action get <id>` | Show a row-action with its YAML |
| `shp row-action create --sheet <sheetId> --name <n> --trigger <created\|updated\|deleted\|demand> [--yaml <file>] [--disable] [--enabled-expr <pred>] [--params-def <json>] [--fire-field …]... [--fire-condition <json>]` | Create a row-action with everything set in one step |
| `shp row-action update <id> [--name] [--yaml <file>] [--enable/--disable] [--enabled-expr <pred>] [--params-def <json>] [--fire-field …]... [--fire-condition <json>] [--no-fire-condition]` | Change a row-action |
| `shp row-action run <id> <rowId> [--params <json>] [-p key=value]...` | Run an on-demand row-action on a row |
| `shp row-action executions <id> [--limit n]` | Recent runs |
| `shp row-action delete <id> [--force]` | Delete |

**Fire conditions** (automatic triggers) make a row-action run only for relevant changes — and stop an `OnSheetRowUpdated` action that edits its own row from triggering itself again.

- `--fire-field <field>` — updated: the field changed; created/deleted: the field has a value
- `--fire-field <field>=<value>` — updated: changed **to** the value; created/deleted: equals the value
- `--fire-field <field>=<from>-><to>` — updated only: changed from one value to another (either side may be empty)
- Repeat `--fire-field` to require several (all must hold). For OR, groups or negation, pass the full JSON with `--fire-condition` (see [Fire Conditions](reference/sheetyapp-row-action.md#fire-conditions)).
- `--no-fire-condition` removes it, so the action runs on every event of its trigger.
- Values are read as JSON when they parse (`5`, `true`, `null`), else as text. **Select columns take option IDs**, not labels. Field names and option IDs are checked against the sheet before anything is saved.
- `--enabled-expr` and `--params-def` are for on-demand actions only; fire conditions are for automatic ones only.

```bash
shp row-action create --sheet 3 --name "Notify on ship" --trigger updated --yaml notify.yaml \
  --fire-field 'status=<openOptionId>-><shippedOptionId>'
shp row-action create --sheet 3 --name "Approve" --trigger demand --yaml approve.yaml \
  --enabled-expr '@status = t::css.orders.status:'"'"'<pendingOptionId>'"'"'' --params-def '[{"nameId":"note","datatype":"string"}]'
```


### Procedures
| Command | Purpose |
|---------|---------|
| `shp procedure list / get <id>` | List or show procedures |
| `shp procedure create --name <n> [--yaml <file>] [--params-def <json>]` | Create a procedure |
| `shp procedure update <id> [--name] [--yaml] [--params-def]` | Change a procedure |
| `shp procedure run <id> [--params <json>] [-p key=value]...` | Run a procedure |
| `shp procedure executions <id>` / `delete <id> [--force]` | Runs / delete |

### Timing Actions
| Command | Purpose |
|---------|---------|
| `shp timing-action list / get <id>` | List or show timing actions |
| `shp timing-action create --description <d> --cron "<expr>" [--yaml]` | Recurring action |
| `shp timing-action create --description <d> --query <queryId> --column <dateColumnNameId> [--yaml]` | Scheduled action, run at each row's date in the query |
| `shp timing-action update <id> [--description] [--cron \| --query --column] [--yaml] [--enable/--disable]` | Change |
| `shp timing-action run <id>` | Run now |
| `shp timing-action occurrences [--ids a,b] [--until <ISO date>]` | Planned runs (up to 7 days ahead) |
| `shp timing-action executions <id>` / `delete <id> [--force]` | Runs / delete |

### Workflow Executions
| Command | Purpose |
|---------|---------|
| `shp workflow activity` | Your recent workflow executions in the workbook |
| `shp workflow logs <executionId>` | Step-by-step log of one execution |
| `shp workflow dismiss <executionId>` | Remove an execution from your activity list |

Workflows run in the background: `run` commands only **queue** the execution. Check the outcome with `executions` and `workflow logs`.

**Parameter definitions** (`--params-def`) are a JSON array of `{ "nameId", "datatype", "predefinedOptions"? }`. Use lowercase Q-Expression datatypes — `string`, `number`, `boolean`, `datetime` — or `srr.<sheetNameId>` (a row), `_s.srr.<sheetNameId>` (several rows), `css.<sheetNameId>.<columnNameId>` / `cms.…` (select options):
```bash
shp row-action update <id> --params-def '[{"nameId":"note","datatype":"string"},{"nameId":"approver","datatype":"srr.staff"}]'
shp row-action run <id> 1017 -p note="Approved by phone" -p approver=12
```

### API Templates
Reusable, parameterized HTTP calls to external systems, run from workflows with `invokeTemplatedApi`. Addressed by **nameId**.

| Command | Purpose |
|---------|---------|
| `shp api-template list / get <nameId> [--json]` | List or show API templates |
| `shp api-template create --name <n> --verb <verb> --url '<Q-Text>' [--payload '<Q-Text>'] [--header 'Name=<Q-Text>']... [--param nameId=datatype]...` | Create one; prints its nameId |
| `shp api-template update <nameId> [same options]` | Change one — unspecified settings are kept; `--header` and `--param` replace **all** existing headers / parameters; `--payload ''` removes the payload |
| `shp api-template run <nameId> [-p name=value]... [--params <json>]` | **Calls the external API for real** through the template and prints the response |
| `shp api-template delete <nameId> [--force]` | Delete one |

- `--verb`: `Get`, `Post`, `Put`, `Patch` or `Delete`.
- `run` sends a real request with real side effects (a message posted, an order created…). **Confirm with the user before running a template that changes anything**, and prefer a test endpoint or harmless values when one exists. `-p` values are read as JSON when they parse (`3`, `true`), otherwise as text.
- URL, payload and header values are **Q-Text**. The template's **parameters are its variables**: `{{orderId}}` or `{% q $orderId %}`. Secrets: `{% q $_SECRET_<nameId> %}` (never paste a secret value into a template). Fields: `{% q $_f_<nameId> %}`.
- `--param nameId=datatype` declares a parameter; use lowercase datatypes (`string`, `number`, `boolean`, `datetime`, `srr.<sheetNameId>`, …). Workflows pass values for them in `templateParameterQExpressionDef`.
- `--payload` takes inline Q-Text, a file path, or `-` for stdin — write longer JSON payloads to a file first.
- `--spec <json>` passes the whole definition (`name`, `urlQText`, `jsonPayloadQText`, `headerQTexts`, `apiVerb`, `parameters`); flags override it.
- **Create and update check the Q-Text first** and save nothing if it is invalid — including any variable that is not a parameter, field, secret or `$ActingMember`, since that would always be empty at runtime. `--skip-check` saves anyway. The check covers `{% q %}` expressions; plain `{{name}}` references aren't checked, so spell them exactly as the parameter nameIds.

```bash
shp api-template create --name "Notify Slack" --verb Post \
  --url 'https://hooks.slack.com/services/{% q $_SECRET_slackHookPath %}' \
  --payload '{ "text": "Order {{orderNumber}}: {% q $total %} USD" }' \
  --header 'Content-Type=application/json' \
  --param orderNumber=string --param total=number
```

### Q-Functions
Custom JavaScript functions, callable from any Q-Expression like a built-in: `addTax(@amount, $_f_taxRate)`. Addressed by **name** (case-sensitive).

| Command | Purpose |
|---------|---------|
| `shp q-function list / get <name> [--json]` | List or show q-functions (`get` includes the script) |
| `shp q-function create --name <n> --script <file\|'js'\|-> --output <datatype> [--arg name=datatype]... [--type-conversion]` | Create one |
| `shp q-function update <name> [--script …] [--output …] [--arg name=datatype]... [--no-args] [--type-conversion\|--no-type-conversion]` | Change one — unspecified settings are kept; `--arg` replaces **all** arguments |
| `shp q-function run <name> [-a name=value]... [--args <json>] [--json]` | Run the saved function on the server with test values and print the result |
| `shp q-function datatypes [--json]` | Datatypes that arguments and outputs may use in this workbook |
| `shp q-function delete <name> [--force]` | Delete one |

- **The script is a function body**: arguments are available by their names, and the result is returned with `return` (`return amount * (1 + rate);`). Write longer scripts to a `.js` file and pass the path.
- **Argument order is call order**: `--arg amount=number --arg rate=number` means `addTax(amount, rate)`. The number of arguments in a call isn't checked — anywhere: a missing one simply arrives as `null` — so pass exactly as many as declared, and guard against `null` in the script.
- **Datatypes** are Q-Expression types: `string`, `number`, `boolean`, `datetime`, `unknown`, `mem`, a row `srr.<sheetNameId>`, a row list `_s.srr.<sheetNameId>`, or a select column's type (`css.<sheet>.<column>` …). `shp q-function datatypes` lists exactly what this workbook accepts.
- **Names**: start with a letter; letters, digits, underscores; can't reuse a built-in function name (`If`, `Round`, `CountList`, …). Argument names can't be JavaScript reserved words or globals (`new`, `Date`, `Math`, …).
- **Sandbox**: no network, files or DOM; about 2 s, 2 MB and 5,000 statements per call; dates use the workbook's time zone.
- `create` and `update --script` check the JavaScript **syntax** locally first and save nothing on an error (`--skip-check` saves anyway). Syntax isn't behaviour — **always `run` a new or changed function** with realistic values before using it.
- `run` values: `-a amount=100` is read as JSON when it parses (`100`, `true`, `[1,2]`, `"text"`), otherwise as text. A row argument (`srr.<sheet>`) takes the row ID and the server passes the full row.
- Typical uses: date math (Q-Expression has no date arithmetic), `Now()`, formatting, text parsing, aggregations over lists.
- After creating a function, check expressions that use it with `shp qexpr check` — it reads the workbook's q-functions.

```bash
cat > daysBetween.js <<'EOF'
if (!from || !to) return 0;
return Math.round((new Date(to) - new Date(from)) / 86400000);
EOF
shp q-function create --name daysBetween --script daysBetween.js --output number --arg from=datetime --arg to=datetime
shp q-function run daysBetween -a from='"2025-01-01"' -a to='"2025-03-01"'
shp qexpr check 'daysBetween(@startDate, @endDate) > 30' --sheet projects --expect boolean
```

### Workbook Apps and Widgets
Dashboards built from widgets. An app has **references** (rows of a sheet or query, `$_ref_<nameId>`), **parameters** (viewer inputs, `$_par_<nameId>`), **compute references** (calculated values, `$_cref_<nameId>`) and **widgets** laid out on a 12-column grid. Workbook fields (`$_f_<nameId>`) are available too.

| Command | Purpose |
|---------|---------|
| `shp app list [--json]` | List apps |
| `shp app get <appId> [--json]` | An app's references, parameters, compute references and widgets, with their IDs |
| `shp app create --name <n>` / `rename <appId> --name <n>` / `delete <appId> [--force]` | Create, rename, delete |
| `shp app reference add <appId> --name <n> --sheet <sheetId> [--query <queryId> \| --filter '<pred>']` | Add a reference; prints its `$_ref_<nameId>` |
| `shp app reference update <appId> <nameId> [same options]` / `remove <appId> <nameId> [--force]` | Change / remove |
| `shp app reference data <appId> <nameId> [--json]` | The rows a reference returns now |
| `shp app parameter add <appId> --name <n> --datatype <type> [--default <v>] [--default-expr '<expr>']` | Add a parameter; prints its `$_par_<nameId>` |
| `shp app parameter update <appId> <nameId> [same options]` / `remove …` | Change / remove |
| `shp app compute add <appId> --name <n> --expr '<expr>'` | Add a compute reference (its type is inferred); prints its `$_cref_<nameId>` |
| `shp app compute update <appId> <nameId> [--name] [--expr]` / `remove …` | Change / remove |
| `shp app widget add <appId> --type <type> [options]` | Add a widget |
| `shp app widget update <appId> <widgetId> [options]` | Change a widget's content, or move/resize it |
| `shp app widget get <appId> <widgetId>` / `remove <appId> <widgetId> [--force]` | Show one as JSON / remove it |
| `shp app publish <appId> [--auth authenticated\|whitelisted\|anonymous] [--ips <list>]` | Publish at a public link (or change its access) |
| `shp app public <appId>` / `unpublish <appId> [--force]` | Show the public link / stop publishing |

**Widget types and their options**

| `--type` | Shows | Options |
|----------|-------|---------|
| `grid` | Rows in a table | source; `--set hiddenColumns='["col"]'`, `--set allowedRowActionIds='["<id>"]'` |
| `bar` | Bar chart | source; `--x-axis`, `--value` (repeatable: one series each), `--group-by` (one value only), `--agg` |
| `line` | Line chart | source; `--x-axis`, `--value`, `--group-by`, `--agg` |
| `pie` | Pie chart | source; `--legend`, `--value`, `--agg` |
| `heatmap` | Heat map | source; `--x-axis`, `--y-axis`, `--value`, `--agg`; `--set spanEndColumnNameId=…`, `maxValue=…` |
| `gantt` | Gantt chart | source; `--set taskNameColumnNameId=… startDateColumnNameId=… endDateColumnNameId=…` (required), plus optional `durationColumnNameId`, `progressColumnNameId`, `parentTaskColumnNameId`, `finishToStartTaskColumnNameId`, `descriptionColumnNameId` |
| `text` | Q-Text | `--template '<Q-Text>'` (inline, file or `-`) |
| `parameter` | Input for a parameter | `--parameter <parameterNameId>` |

- **Source** (data widgets): `--query <queryId>` (the sheet is taken from the query), or `--direct --sheet <sheetId> [--filter '<pred>']` to read the sheet's rows directly. A direct filter may use app variables, e.g. `@amount > $_par_minAmount`.
- `--agg`: `Sum`, `Count`, `Avg`, `Max` or `Min`; non-numeric value columns only allow `Count`.
- `--label` sets the widget title. `--set name=value` sets any other content property (camelCase; the value is read as JSON when it parses), and `--spec <json>` passes the whole content definition.
- **Layout**: `--col` (0–11), `--row`, `--width` (1–12), `--height` (rows of 30 px). New widgets go below the existing ones at width 6 and height 10 (3 for a parameter input) unless given.
- `update` keeps everything not passed; a widget's type can't change — remove it and add a new one.
- **Checks before saving**: direct filters and compute references are checked as Q-Expressions with the app's variables, text templates as Q-Text, and a parameter widget's parameter must exist — any unknown variable is an error. The server then checks the rest (required fields, that the query matches the sheet, that columns exist in the query's result, aggregation vs column type) and refuses the save with a message.
- Pick **human-readable** columns for labels (task names, categories, legends), not IDs or GUIDs — add a query compute column with RowRef dot access such as `@project.name` when needed.
- **Publishing makes data visible outside the workbook.** `anonymous` means anyone with the link, without signing in. Confirm with the user before publishing, and prefer `authenticated`.

```bash
APP=$(shp app create --name "Sales" | grep -o 'ID: [^)]*' | cut -d' ' -f2)   # or read the ID from the output
shp app parameter add $APP --name "Min amount" --datatype number --default 100
shp app widget add $APP --type parameter --parameter minAmount --width 4
shp app widget add $APP --type bar --label "Revenue by region" --query <queryId> --x-axis region --value amount --agg Sum
shp app widget add $APP --type pie --direct --sheet 3 --filter '@amount > $_par_minAmount' --legend region --value amount --agg Count --col 6
shp app reference add $APP --name "Orders" --sheet 3
shp app compute add $APP --name "Order count" --expr 'CountList($_ref_orders)'
shp app widget add $APP --type text --template 'Orders: {% q $_cref_orderCount %}' --width 4
```

### Webhooks
Workflows started by an external system calling a URL. The request's JSON body is `$_body` in the YAML.

| Command | Purpose |
|---------|---------|
| `shp webhook list [--json]` | List webhooks |
| `shp webhook get <id> [--json]` | Show one, with its YAML and **trigger URL** |
| `shp webhook create [--description <d>] [--yaml <file>]` | Create one; prints the trigger URL |
| `shp webhook update <id> [--description <d>] [--yaml <file>]` | Change one |
| `shp webhook run <id> [--payload <json\|file\|->]` | Trigger it with a test body, as the external system would |
| `shp webhook events <id> [--limit n] [--json]` | Recent calls received and their outcome |
| `shp webhook event <id> <eventId> [--json]` | One call, including its request body |
| `shp webhook delete <id> [--force]` | Delete one |

- The trigger URL (`<API>/webhook-triggers/<id>`) accepts an **anonymous** POST: whoever has the URL can trigger it. Share it only with the system that calls it, and validate `$_body` in the YAML before writing data.
- Webhooks can't be enabled or disabled through the API — delete one to stop it.
- Check expressions that read the body by declaring it: `shp qexpr check '$_body.amount > 0' --var _body.amount=number`.
- `run` queues the workflow like a real call; check `shp webhook events` and `shp workflow logs <executionId>` for the result.

### Workbook Fields
Single, typed workbook-level values, read as `$_f_<nameId>` in workflows and apps (e.g. a tax rate, a default owner). Addressed by **nameId**, which is generated from the name.

| Command | Purpose |
|---------|---------|
| `shp field list / get <nameId> [--json]` | List or show fields |
| `shp field create --name <n> --datatype <type> [--value <v>]` | Create one; prints the `$_f_<nameId>` to use |
| `shp field update <nameId> [--name] [--datatype] [--value <v> \| --clear-value]` | Change one — unspecified settings are kept |
| `shp field delete <nameId> [--force]` | Delete one |

- `--datatype` is a lowercase Q-Expression type (`string`, `number`, `boolean`, `datetime`, `srr.<sheetNameId>` for a row, `_s.srr.<sheetNameId>` for rows); it's checked against `shp q-function datatypes`.
- `--value` is read as JSON when it parses (`0.08`, `true`, `[1,2]`), else as text. A row field takes the row ID (or an array of IDs).

### Expression Checks (offline)
| Command | Purpose |
|---------|---------|
| `shp qexpr check '<expr>' [--sheet <sheet>] [--workflow-sheet <sheet>] [--var name=type]... [--expect <type>]` | Validate a Q-Expression and show its output type |
| `shp qtext check '<template>' [same context options]` | Validate a Q-Text template and every `{% q %}` expression in it |

Both run locally with the same parser and type checker as the server — nothing is saved or executed. See [Validate Before Saving](#validate-before-saving).

### Not Available Through `shp`
These must be done in the web app (link the user to the page):
- Secrets (the agent should never handle secret values — tell the user which nameId to create)
- Row triggers and row-form preferences (field order, info panel)
- Members, registrations and delegation (Connected Apps)

---

## 6. Q-Expression Essentials

Full reference: [sheetyapp-q-expression.md](reference/sheetyapp-q-expression.md).

### Syntax
- Column: `@columnNameId` — always the **nameId**, case-sensitive
- Variable: `$name`; nested values with dots: `@customer.name`, `$_row.total`
- Literals: `123`, `'text'`, `TRUE`/`FALSE`, dates `#2025-04-12#`, custom types `t::<type>:'value'`
- Operators: `+ - * / % ^`, `= != < > <= >=`, `AND`, `OR`, parentheses; `+` concatenates when either side is text
- Built-in functions — these 37, case-sensitive, nothing else:
  * Math: `Abs`, `Acos`, `Asin`, `Atan`, `Atan2(y, x)`, `Ceil`, `Cos`, `Cosh`, `Exp`, `Floor`, `Log`, `Log10`, `Max(a, b)`, `Min(a, b)`, `Pow(base, exp)`, `Round(n[, decimals])`, `Sign`, `Sin`, `Sinh`, `Sqrt`, `Tan`, `Tanh`, `Truncate`
  * Logic and conversion: `If(cond, a, b)`, `IsBlank(x)`, `ToString`, `ToNumber`, `ToBoolean`, `ToDateTime`
  * Lists: `CountList(list)`, `PickItemInList(list, i)`, `PickFirstItemInList(list)`, `PickLastItemInList(list)`, `ContainItemInList(list, x)`
  * Text (case-sensitive): `ContainText(t, s)`, `StartWithText(t, s)`, `EndWithText(t, s)`
  * `Max`/`Min` take exactly two arguments. `ToNumber`/`ToBoolean` **fail** on text they can't convert (including `''`), and `If` can't guard them — **`If` evaluates both branches** — so use a q-function for conversions that may fail. `ToNumber('1,5')` is 15 (comma = thousands separator). Write dates as ISO text or `#2025-04-12#` literals. `IsBlank(' ')` is true. Details: [sheetyapp-q-expression.md](reference/sheetyapp-q-expression.md#built-in-functions)
- Workbook q-functions are called the same way; check they exist in the snapshot's `qFunctions` first

### Row-Aware vs Row-Agnostic
Decide which context an expression runs in **before** writing it:
- **Row-Aware** (computed columns, query filters, `row search --expr`, validation, `allowEditQExpression`, `enabledQExpression`, row-aware workflow parameters): `@column` refers to the current row's columns — only columns of **that** sheet.
- **Row-Agnostic** (most workflow parameters, procedure outputs): no current row — **never use `@column`**; use variables such as `$_row.column`.
- In a computed column, never reference the column itself.

### Rules and Frequent Mistakes
- **No `null`**: there is no null literal. Use `''` for text and `0` for numbers, or `IsBlank(...)`.
- **No text ordering**: `@name < 'a'` is illegal. `<`, `>`, `<=`, `>=` only work on numbers and dates.
- **No date arithmetic**: `@end - @start` is illegal. Write a q-function for date math (`shp q-function create`).
- **No Excel functions**: there is no `SUM`, `COUNT`, `AVERAGE`, `TODAY`, `NOW`, `CONCATENATE`, `COALESCE`, `VLOOKUP`. Use `+`, `CountList`, lookups, or q-functions. Never assume a function exists.
- **Strict types**: convert explicitly (`ToString(@qty)`) when mixing text and numbers.
- **Select columns store option IDs, not labels**. Compare against the option literal: `@status = t::css.<sheetNameId>.<columnNameId>:'<optionId>'` (`cms` for MultiSelect), or compare the label with `@status.Text = 'Done'`. Never `@status = 'Done'` — it compares the ID with the label and is always false. Prefer the `t::` literal in filters: `@status = 'o-done'` (ID as plain text) is typed `unknown`, which query filters reject.
- **RowRef columns** hold the referenced row's ID; read its columns with dot notation: `@customer.email`.
- **Member columns** hold the IdpSub; `.Name` and `.Email` give details: `@assignee = $ActingMember.IdpSub`.
- **Lookups**: `$value:<sheetNameId>@<matchColumnNameId>:<selectColumnNameId>`. Use exact nameIds from the snapshot and make sure the match column holds unique values. The input **must be a variable** (or a literal) — `@column` as the input is forbidden:
  * Valid: `$customerId:customers@id:name`, `$_row.code:customers@code:name`
  * Forbidden: `@customerCode:customers@code:name`
  * Workaround: use RowRef dot access, e.g. `@customerRef.name`
- **Meta properties** (`@__Id`, `@__CreatedAtUtc`, `@__UpdatedAtUtc`, `@__ChangedAtUtc`) can be used in any expression, e.g. `@__CreatedAtUtc > #2025-08-01#`. They are read-only — never write to them.

### Useful Variables
- `$ActingMember.IdpSub`, `.Name`, `.Email`, `.Role`, `.ClientId`
- `$_f_<fieldNameId>` (workflows, apps), `$_SECRET_<nameId>` (workflows, API templates)
- Workflow: `$_row`, `$_oldRow`, `$_rowMetadata.RowId`, `$_body`, parameters, instruction outputs

### Validate Before Saving
**Always run `shp qexpr check` on every expression before saving it** — in a column, query, row-action, procedure, timing action or association. It checks syntax, column and variable names, function names, lookups, operator types and select options (an option literal's ID must exist; a select column compared with a label is an error), and prints the output type. `shp qtext check` also checks `{{name}}` references. Exit code 0 means valid, 1 invalid; add `--json` to parse the result.

Pick the context the expression will run in:

| Expression runs in | Options |
|--------------------|---------|
| Computed column, query filter, validation rule, `allowEditQExpression`, `enabledQExpression`, `filterQPredicate` | `--sheet <sheet>` (Row-Aware) |
| Row-agnostic workflow parameter in a row-action | `--workflow-sheet <sheet>` (adds `$_row`, `$_oldRow`, `$_rowMetadata`) |
| Row-aware workflow parameter (e.g. `filterQPredicate` on another sheet) | `--sheet <targetSheet> --workflow-sheet <rowActionSheet>` |
| Procedure / timing action / webhook | no `--sheet`; declare parameters and inputs with `--var` |
| Workbook app widgets and compute references | checked automatically by `shp app widget add/update` and `shp app compute add/update` (with the app's `$_ref_`, `$_par_`, `$_cref_` variables) |

Declare anything else the expression reads with `--var name=datatype`: on-demand or procedure parameters, earlier `outputVarName`s, iterator variables (`--var order=srr.orders` gives `$order.<column>` too). Undeclared variables are reported as warnings, typed `unknown`.

```bash
shp qexpr check '@status = t::css.orders.status:'"'"'<optionId>'"'"' AND @amount > 1000' --sheet orders --expect boolean
shp qexpr check '$_row.amount * $_f_taxRate' --workflow-sheet orders
shp qexpr check 'CountList($openOrders) = 0' --workflow-sheet orders --var openOrders=_s.srr.orders --expect boolean
shp qtext check 'Order {{_row.orderNumber}} total {% q $_row.total %}' --workflow-sheet orders
```

- Use `--expect boolean` for filters, conditions and validation rules.
- Quote expressions in **single quotes** so the shell keeps `$` and `@`; for long ones pass a file path or `-` (stdin).
- It reads the workbook's sheets, q-functions and fields via `--workbook` / the default workbook, or offline from `--snapshot <file>` (`shp workbook export -o <file>`). Without either, only built-in functions are known.
- Secret names aren't checked: any `$_SECRET_<name>` is accepted as text.
- `shp qexpr check` validates, it doesn't test logic. To see which rows a predicate matches, run `shp row search <sheetId> --expr '<predicate>' --json`.

**Server-side typing gotcha** the check catches: a function result can't feed `AND`, `OR` or `If()` directly — the server types it as `object`. Compare it explicitly: `ContainText(@title, 'x') = TRUE AND @amount > 1`, `If(StartWithText(@code, 'A') = TRUE, 1, 0)`. The web editor accepts the short form, but workflows, computed columns and queries evaluated on the server fail.

---

## 7. Q-Text Essentials

Full reference: [sheetyapp-q-text.md](reference/sheetyapp-q-text.md).

- Liquid templates: `{{name}}` inserts a value, `{% if %}…{% endif %}` and filters work as usual
- `{% q <Q-Expression> %}` evaluates a Q-Expression (variables need `$` inside the tag)
- Use `{% q %}` for values reached through a column (`{% q $_row.customer.name %}`), member `.Name`/`.Email`, select `.Text`, and any math or logic
- Contexts: API templates (template parameters), workflow `sendNotification` / `waitForApproval` (workflow variables, e.g. `{{_row.orderNumber}}`), sheet associations (`$_associatedRows`), app Q-Text widgets
- Sheet association templates are set with `shp association update … --eval-text`, e.g. `"{% q CountList($_associatedRows) %} orders"`

---

## 8. Building Workflows

Full references: [sheetyapp-row-action.md](reference/sheetyapp-row-action.md) and [sheetyapp-row-action-yaml-instruction.md](reference/sheetyapp-row-action-yaml-instruction.md).

### Procedure
1. Read the workbook snapshot: sheet IDs, nameIds, column nameIds and types, option IDs, existing procedures and API templates (`shp api-template list`). If the workflow calls an external system, create the API template first (`shp api-template create`).
2. Pick the workflow kind: row-action (row events or on demand), timing action (schedule), procedure (reusable steps).
3. Write the YAML to a file, choosing the right context (Row-Aware / Row-Agnostic) for every expression.
4. Check every expression with `shp qexpr check` (and every Q-Text message with `shp qtext check`) in its context — saving the YAML only validates its structure, not the expressions inside.
5. Create or update it with `shp`, passing `--yaml <file>`.
6. Test it: `shp row-action run <id> <rowId>` (on-demand), make a real row change (automatic triggers), or `shp procedure run` / `shp timing-action run`.
7. Check `shp row-action executions <id>` and `shp workflow logs <executionId>`, then fix and repeat.

### YAML Shape
```yaml
execInstructions:
- type: querySheet
  queryingSheetNameId: "orders"
  filterQPredicate: "@customer = $_row.customer"   # Row-Aware: columns of 'orders' rows
  outputVarName: "customerOrders"
- type: patchSheetRowByRowRef
  rowRefGetterQExpression: "$_rowMetadata.RowId"   # the triggering row
  patchColumnByQExpressionDef:
    orderCount: "CountList($customerOrders)"
```
- The root key is `execInstructions`. Every instruction has `type`; optional `description` and `exitOnCompleted`.
- Quote every expression in double quotes, with text literals in single quotes: `"'pending'"`.

### Variables
| Variable | Available in |
|----------|-------------|
| `$_row` (triggering row), `$_rowMetadata.RowId`, `$_rowMetadata.SheetNameId` | Row-actions |
| `$_oldRow` (values before update / deleted values) | OnSheetRowUpdated, OnSheetRowDeleted |
| `$<parameterNameId>` | On-demand row-actions, procedures |
| `$_body` | Webhooks |
| `$_f_<field>`, `$_SECRET_<secret>`, `$ActingMember` | All workflows |

There is **no `$entity`** variable — use `$_row`.

### Instruction Types
| Type | Does | `@column` allowed in |
|------|------|----------------------|
| `querySheet` | Rows matching a filter → list variable | `filterQPredicate` |
| `runQExpression` | Evaluate → variable | — |
| `runQExpressionWithRowRefContext` | Evaluate against one referenced row | `qExpression` |
| `patchSheetRow` | Update all rows matching a filter (same values for each) | `selectTargetQPredicate` only |
| `patchSheetRowByRowRef` | Update one row by row reference (e.g. `$_rowMetadata.RowId`) | patch values |
| `patchSheetRowByRowId` | Update one row by ID | patch values |
| `addSheetRow` | Create a row | — |
| `upsertSheetRow` | Update matching rows or create one | filter and values |
| `execConditionalFlow` | If / else branches | — |
| `switch` | Branch on a value (`cases`, `defaultInstructions`) | — |
| `iterateCollection` | Loop over a list | — |
| `invokeTemplatedApi` | Call an API template | — |
| `invokeProcedure` / `exitProcedureWithOutput` | Call a procedure / return a value from one | — |
| `sendNotification` | Notify all workbook members (Q-Text message) | — |
| `exitRowActionWithMessage` | Stop and show a message to the user (not in procedures) | — |
| `delay` | Wait (`'PT30M'`, `'P1D'`) | — |
| `waitForApproval` | Ask a member to approve/reject, then branch | — |

### Workflow Rules and Frequent Mistakes
- `$_row.__Id` is a number, not a row reference: use `$_rowMetadata.RowId` (or a RowRef column such as `$_row.customer`) for `rowRefGetterQExpression`.
- Don't use `@column` in Row-Agnostic parameters; in `patchSheetRow` patch values it isn't available at all.
- Select values written by workflows must be option IDs (`"t::css.orders.status:'<optionId>'"` or the ID text), not labels.
- Workflow writes ignore row restrictions but still run validation; a rejected write doesn't fail the step, so validate first.
- An `OnSheetRowUpdated` row-action that updates its own row can retrigger itself — give it a fire condition (`--fire-field status=<fromId>-><toId>`) or a guard in the YAML (compare `$_row` with `$_oldRow`).
- Each sheet runs only one row-action per automatic trigger type — extend the existing one rather than adding a second.
- Never put secret values into rows or notifications.

---

## 9. Web App Links

The web app's base URL is in **`$SHEETYAPP_WEB_URL`** (production: `https://go.sheetyapp.com`) — `echo $SHEETYAPP_WEB_URL` if you need to confirm it for this server. Build links from the routes in [sheetyapp-sitemap.md](reference/sheetyapp-sitemap.md), filling in real values (`workbookId` from `shp workbook list`, sheet nameId, IDs). Common ones:

| Page | Path |
|------|------|
| Workbook home | `/workbooks/<workbookId>` |
| Sheet rows | `/workbooks/<workbookId>/sheets/<sheetNameId>` |
| A row | `/workbooks/<workbookId>/sheets/<sheetNameId>/rows/<rowId>` |
| Sheet settings | `/workbooks/<workbookId>/sheets/<sheetNameId>/config` (tabs `#constraints`, `#row-triggers`, `#restriction`) |
| Columns designer | `/workbooks/<workbookId>/sheets/<sheetNameId>/columns` |
| Row-action designer | `/workbooks/<workbookId>/row-actions/<rowActionId>/design` |
| Query | `/workbooks/<workbookId>/queries/<queryId>` |
| Apps | `/workbooks/<workbookId>/apps` |
| Q-functions | `/workbooks/<workbookId>/q-functions` |
| Fields | `/workbooks/<workbookId>/fields` |
| API templates | `/workbooks/<workbookId>/api-templates` |
| Secrets | `/workbooks/<workbookId>/secrets` |
| Webhooks | `/workbooks/<workbookId>/webhooks` |
| Connected Apps (CLI delegation) | `/workbooks/<workbookId>/settings#connected-apps` |

---

## 10. Guidance for Things Done in the Web App

When the user needs something `shp` can't do, explain what to set up and link the page.

### Secrets
- Created on the Secrets page; the agent never sees their values
- Referenced by nameId as `$_SECRET_<nameId>` in API templates and workflows — tell the user which nameId to create when an API template needs a credential

