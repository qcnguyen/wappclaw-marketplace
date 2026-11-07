# Understanding and Using Q-Expression

Q-Expression is the formula language used throughout SheetyApp. It resembles Excel formulas, but works on named columns, variables and related sheets, and can be extended with JavaScript q-functions. This guide covers Q-Expression syntax and usage patterns.

## Where Q-Expression Is Used

- **Computed columns** (`computeColumnQlangExpression`): values calculated from other columns
- **Filters**: saved queries (`filterQPredicate`), app references, workflow queries
- **Validation rules** and **permission rules** (`allowRowManipulationQExpression`, `allowEditQExpression`)
- **Row-action availability** (`enabledQExpression`)
- **Workflows**: almost every YAML instruction parameter (see the [YAML Instruction Reference](sheetyapp-row-action-yaml-instruction.md))
- **Q-Text templates**, inside `{% q ... %}` tags (see [Q-Text](sheetyapp-q-text.md))
- **Workbook apps**: compute references and parameter defaults

## Basic Syntax Overview

### Data Types and Literals
- **Numbers**: `123`, `45.67`
- **Strings**: `'Hello World'` (single quotes)
- **Booleans**: `TRUE` or `FALSE` (case-insensitive)
- **Dates**: `#2025-04-12#` (enclosed in `#`)
- **Custom types**: `t::typeName:'value'`

### Operators
- **Arithmetic**: `+`, `-`, `*`, `/`, `%` (modulo), `^` (exponent)
- **Text concatenation**: `+` when either side is text: `'Order #' + @orderNumber`
- **Comparison**: `=`, `!=`, `<`, `>`, `<=`, `>=`
- **Logical**: `AND`, `OR`
- **Grouping**: parentheses `( ... )`

There is no `NOT` operator or `null` literal. Use `!=`, `= FALSE`, `If(...)` or `IsBlank(...)` instead.

### Typing Rules
Q-Expression is strictly typed:
- Arithmetic (`-`, `*`, `/`, `%`) works only on numbers; `+` works on numbers or concatenates text
- `<`, `>`, `<=`, `>=` work only on two numbers or two dates
- Text comparison with `=` is case-sensitive
- Blank values count as `0` in number arithmetic and as `''` in text, so `@discount + 1` is `1` when `@discount` is empty
- Use the conversion functions (`ToNumber`, `ToString`, …) to mix types
- A function's result can't be used directly as a condition in `AND`, `OR` or `If()` when the expression is evaluated on the server (workflows, computed columns, queries). Compare it explicitly: `ContainText(@title, 'urgent') = TRUE AND @priority > 1`, `If(StartWithText(@code, 'A') = TRUE, 1, 0)`

### References
- **Column references**: `@columnName` — a column of the current row
- **Variables**: `$variableName` — a value supplied by the context (see [System Variables](#system-variables))
- **Nested properties**: `@customer.name`, `$_row.order.total` (dot notation)
- **Function result properties**: `myFunction(@x).propertyName`
- **Meta properties**: `@__Id`, `@__CreatedAtUtc`, … (see below)

### Column Value Shapes
Some column types expose extra properties:
- **RowRef**: the value is the referenced row's ID; reach the referenced row's columns with dot notation: `@customer.email`, `@order.customer.name`
- **Member**: the value is the member's IdP subject (IdpSub); `.Name` and `.Email` give the member's name and email: `@assignee.Email`
- **SingleSelect / MultiSelect**: the value is the selected option ID(s); `.Text` gives the option label(s): `@status.Text = 'Done'`. To compare with an option, use the option literal `t::css.<sheetNameId>.<columnNameId>:'<optionId>'` (`cms` for MultiSelect) — comparing the column with a label (`@status = 'Done'`) is always false

### Meta Properties

Every row has built-in, read-only meta properties:

- **@__Id** - The unique numeric identifier of the row
- **@__CreatedAtUtc** - When the row was created (UTC)
- **@__UpdatedAtUtc** - When the row was last updated (UTC)
- **@__ChangedAtUtc** - When the row's data last changed (UTC)

```
// Rows created after a date
@__CreatedAtUtc > #2025-08-10#

// Rows changed after a date
@__ChangedAtUtc > #2025-08-01#
```

## Built-in Functions

Functions are called as `FunctionName(arg1, arg2, ...)`. These 37 are all there are. Names are **case-sensitive** (`Round` works, `round` and `ROUND` don't), and each takes exactly the arguments shown.

The results below are what the **server** returns — it evaluates computed columns, filters, queries and workflows. The web app's expression editor previews some conversions differently; those cases are noted.

#### Mathematical Functions
- **Abs(number)** - Absolute value
- **Acos(number)**, **Asin(number)**, **Atan(number)** - Inverse trigonometric functions (radians)
- **Atan2(y, x)** - Arctangent of y/x
- **Ceil(number)** - Round up to the nearest integer
- **Cos(number)**, **Sin(number)**, **Tan(number)** - Trigonometric functions (radians)
- **Cosh(number)**, **Sinh(number)**, **Tanh(number)** - Hyperbolic functions
- **Exp(number)** - e raised to a power
- **Floor(number)** - Round down to the nearest integer
- **Log(number)** - Natural logarithm
- **Log10(number)** - Base-10 logarithm
- **Max(number1, number2)** - The larger of two numbers (exactly two: `Max(a, b, c)` fails — nest instead: `Max(a, Max(b, c))`)
- **Min(number1, number2)** - The smaller of two numbers (exactly two)
- **Pow(base, exponent)** - Power
- **Round(number, decimals)** - Round to a number of decimal places; `decimals` is optional (default 0). Halves round away from zero: `Round(2.5)` = 3, `Round(-2.5)` = -3
- **Sign(number)** - 1, 0 or -1
- **Sqrt(number)** - Square root
- **Truncate(number)** - Remove the fractional part, towards zero: `Truncate(-1.7)` = -1

Out-of-range math doesn't fail: `Sqrt(-1)` is NaN and `Log(0)` is -Infinity — guard with `If(...)` when the input can be 0 or negative.

#### Logical Functions
- **If(condition, trueValue, falseValue)** - Returns one value if the condition is true and another if it is false. **Both values are always evaluated**, whichever is returned — so `If` can't protect an expression that fails (`If(IsBlank(@qty), 0, ToNumber(@qty))` still fails on empty text). Use a q-function for conversions that may fail

#### Type Conversion and Validation Functions
- **IsBlank(value)** - True when the value is missing, empty text, or text of only spaces (`IsBlank(' ')` is true). `0` and `FALSE` are not blank
- **ToString(value)** - Convert to text. Booleans become `'True'` / `'False'` (capitalized; the web editor's preview shows `'true'`)
- **ToNumber(value)** - Convert text to a number: `ToNumber('42')` = 42, `ToNumber('1.5')` = 1.5, surrounding spaces are ignored. Text that isn't a number — including `''` — **fails the evaluation** rather than returning 0, and `If` can't guard it (see above). A comma is read as a thousands separator: `ToNumber('1,5')` = 15. For text that may be empty or invalid, use a q-function, e.g. `return isNaN(parseFloat(v)) ? 0 : parseFloat(v);`
- **ToBoolean(value)** - Convert to a boolean: `'true'`/`'false'` (any case) and numbers (`0` is false). `ToBoolean('false')` is false on the server (the web editor's preview says true), and `''` or other text **fails the evaluation**
- **ToDateTime(value)** - Convert text to a date/time. Use ISO text — `'2025-04-12'`, `'2025-04-12 10:30'` — since other formats (`'12/04/2025'`) are read according to the server's regional settings. Date literals (`#2025-04-12#`) avoid conversion entirely

`ToString` of a date is also formatted by the server's regional settings; format dates in a q-function when the text matters.

#### List Functions
- **CountList(list)** - Number of items in a list (0 if not a list)
- **PickItemInList(list, index)** - Item at a zero-based index (null if out of range)
- **PickFirstItemInList(list)** - First item (null if empty)
- **PickLastItemInList(list)** - Last item (null if empty)
- **ContainItemInList(list, item)** - True when the list contains the item

#### Text Functions
- **ContainText(text, searchText)** - True when text contains searchText
- **StartWithText(text, searchText)** - True when text starts with searchText
- **EndWithText(text, searchText)** - True when text ends with searchText

All text functions are case-sensitive.

There are **no** built-in `TODAY()`, `NOW()`, `SUM()`, `COUNT()`, `AVERAGE()`, `CONCATENATE()` or `COALESCE()` functions. Use `+` for concatenation, `If(IsBlank(...), ...)` for defaults, `CountList` for counts, and q-functions for everything else (for example a `Now()` q-function).

## System Variables

Which variables are available depends on where the expression runs.

#### Current Member (available almost everywhere)
- **$ActingMember** - The workbook member performing the action:
  - **$ActingMember.IdpSub** - The member's unique identifier
  - **$ActingMember.Name** - Display name
  - **$ActingMember.Email** - Email address
  - **$ActingMember.Role** - Role in the workbook: `Owner`, `Admin`, `Contributor`, `SheetWriter` or `SheetReader`
  - **$ActingMember.ClientId** - The client id of the delegated app (e.g. the CLI) the session operates under; null when the user acts directly through the SheetyApp web/mobile app

#### Workbook Fields
- **$_f_<fieldNameId>** - The value of a workbook field (available in workflows and workbook apps), e.g. `$_f_taxRate`

#### Workflow Variables
In row-actions, timing actions, procedures and webhooks: `$_row`, `$_oldRow`, `$_rowMetadata`, `$_body`, parameters, `$_SECRET_<secretNameId>` and the outputs of earlier instructions. See [Workflow Variables](sheetyapp-row-action-yaml-instruction.md#workflow-variables).

#### Workbook App Variables
In workbook app widgets: `$_ref_<referenceNameId>` (app references: sheet rows or saved queries), `$_par_<parameterNameId>` (app parameters entered by the viewer) and `$_cref_<computeReferenceNameId>` (computed references).

#### Sheet Associations
In a sheet association's evaluation template: `$_associatedRows`, the list of associated rows, e.g. `CountList($_associatedRows)`.

#### Registration Auto-Approval
In the registration auto-approval rule: `$Email`, `$Name` and `$Message` of the person registering.

## Q-Functions (Custom JavaScript Functions)

Workbook designers can add their own functions, called **q-functions**, written in JavaScript and callable from any Q-Expression exactly like built-in functions.

```json
{
  "name": "formatCurrency",
  "jsScript": "return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);",
  "outputDataType": "string",
  "argSpec": {
    "amount": "number"
  },
  "isTypeConversionFunction": false
}
```

Usage: `formatCurrency(@price)` returns `$123.45` for a price of 123.45.

How q-functions work:
- `jsScript` is a function **body**: arguments are available by their `argSpec` names, and the result is returned with `return`
- `argSpec` maps argument names to types (`string`, `number`, `boolean`, `datetime`, or other Q-Expression types); `outputDataType` is the result type
- A q-function can take zero arguments, e.g. `Now()` with `"jsScript": "return new Date().toISOString();"`
- Scripts run in a sandbox with no access to the network, files or DOM, and are limited to about 2 seconds, 2 MB of memory and 5,000 statements. Dates use the workbook's time zone
- Exceeding a limit makes the evaluation fail with an inefficient-performance error. A q-function disabled for that reason carries `disableMode: "InefficientPerformance"`
- Q-functions are managed on the workbook's **Q-Functions** page or with `shp q-function` (create, update, run with test values), and appear in snapshots under `qFunctions`

## Lookup Expression

The lookup expression reads a value from another sheet by matching on a column, similar to Excel's `VLOOKUP`:
```
[value]:[sheetNameId]@[matchColumn]:[selectColumn]
```
- **value**: the value to look up (left-hand side of the match). It must be a **variable** (`$customerId`, `$ActingMember.IdpSub`, `$_row.customerCode`), a literal (`'CUST-001'`) or a parenthesized expression — **not a column reference** (`@column`)
- **sheetNameId**: the nameId of the sheet to search
- **matchColumn**: the nameId of the column in that sheet compared with the value
- **selectColumn**: the nameId of the column whose value is returned when a row matches

In plain English: "find the row in `sheetNameId` whose `matchColumn` equals `value`, and return its `selectColumn`."

```
$customerId:customerSheet@id:name
```
Looks up `name` in `customerSheet` from the row whose `id` equals `$customerId`.

```
$_row.customerCode:customers@code:fullName
```
In a workflow: takes the triggering row's `customerCode`, finds the `customers` row whose `code` matches, and returns its `fullName`.

### Lookup Rules
- **Never use a column reference as the input**: `@customerCode:customers@code:fullName` is not allowed. Use a variable as the input, or — when the sheets are linked by a RowRef column — read the referenced row with dot notation instead: `@customer.fullName`.
- **Use nameIds, not display names**, for the sheet and both columns.
- **The match column must hold unique values** in the target sheet. If two rows share the same value, the expression fails with `lookup value ... is duplicated`. Use a key/ID-like column.
- **No match returns blank** (null) — no error.
- **Lookups don't need a RowRef relationship**: the target sheet is searched directly by the match column.
- **Precedence**: a lookup binds tightly, so `1 + $x:sheet@f:s + 1` needs no parentheses around the lookup.
- **Chaining**: two lookups cannot follow each other directly. Wrap the first in parentheses to feed its result into a second lookup:
  ```
  ($a:sheetA@key:refCode):sheetB@code:name
  ```

## Common Patterns

### Filtering
```
@status = 'Completed'
@price > 100 AND @category = 'Electronics'
(@status = 'Pending' OR @status = 'In Progress') AND @priority = 'High'
@assignee = $ActingMember.IdpSub
ContainText(@title, 'urgent')
```

### Calculations
```
@quantity * @unitPrice
(@subtotal + @taxAmount) * (1 - @discountRate)
If(@tier = 'Premium', @price * 0.9, @price)
Round(@total * $_f_taxRate, 2)
@firstName + ' ' + @lastName
```

### Defaults for Empty Values
```
If(IsBlank(@nickname), @firstName, @nickname)
```

### Computed Column
```
// Line total
@quantity * @unitPrice
```

### Validation Rule
```
// End date must be after start date
@endDate > @startDate
```

### Row Manipulation Permission Rule
Example 1 — only owners and admins can change rows:
```
$ActingMember.Role = 'Owner' OR $ActingMember.Role = 'Admin'
```

Example 2 — using a lookup. Allow changes only when the acting member has the 'Clerk' role in the SampleStaff sheet (matching their IdpSub against the SampleMember column and reading the SampleRole column):
```
$ActingMember.IdpSub:SampleStaff@SampleMember:SampleRole = 'Clerk'
```

Example 3 — only the member assigned to the row:
```
@assignee = $ActingMember.IdpSub
```

## Debugging Tips

1. Break complex expressions into smaller parts and test each one
2. Check types — most errors come from mixing text and numbers, or using `<`/`>` on text
3. Check column nameIds and remember that text comparison is case-sensitive
4. For select columns, compare `.Text` with a label, or the column with its option literal (`t::css.…:'<optionId>'`) — never the column with a label. `shp qexpr check` catches this
5. For q-functions, make sure the returned value matches `outputDataType`
