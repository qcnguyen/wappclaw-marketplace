# SheetyApp Workflow YAML Instruction Reference

All SheetyApp automations — **row-actions**, **timing actions**, **procedures** and **webhooks** — are written in the same YAML instruction language. This reference covers the YAML format, the variables each kind of workflow receives, and every available instruction type.

For what row-actions are and how they are triggered, see [SheetyApp Row-Action System Documentation](sheetyapp-row-action.md).

## YAML Format

A workflow definition is a YAML document with a single root key, `execInstructions`, holding the list of instructions to run. Every instruction has a `type` field that selects the instruction.

```yaml
execInstructions:
- type: instructionType
  description: "Optional note shown in logs and the designer"
  exitOnCompleted: false   # Optional: stop the workflow after this instruction
  parameter1: value1
  parameter2: value2
```

Field names are camelCase. Unknown fields are ignored, so a misspelled field name is silently dropped rather than reported — double-check spelling.

### Common Fields (available on every instruction)
- `type` (required): the instruction type, e.g. `querySheet`
- `description` (optional): free-text description of the step
- `exitOnCompleted` (optional, default `false`): when `true`, the workflow stops successfully right after this instruction

### Execution Flow
Instructions run sequentially, top to bottom. Execution stops when:
- An instruction fails (the workflow is marked as failed)
- An `exitRowActionWithMessage` instruction runs
- An `exitProcedureWithOutput` instruction runs (procedures only)
- An instruction with `exitOnCompleted: true` completes
- A `waitForApproval` instruction times out

Workflows run durably in the background, which is what makes long-running steps such as `delay` and `waitForApproval` possible. Every execution is recorded and can be inspected on the workflow's **Executions** page.

## Writing Q-Expressions in YAML

Instruction parameters are Q-Expressions (or Q-Text where noted) written as YAML strings. Wrap every expression in double quotes, and use single quotes for string literals inside it:

```yaml
qExpression: "'pending'"                         # the string literal pending
qExpression: "$_row.quantity * $_row.unitPrice"  # an expression
```

Q-Expression has no built-in `Now()`, `TODAY()`, `SUM()`, `COUNT()` or `COALESCE()` functions. Use the built-in list functions (such as `CountList`) or define a [q-function](sheetyapp-q-expression.md#q-functions-custom-javascript-functions) for anything else. In the examples below, `Now()` is assumed to be a workbook q-function such as:

```json
{ "name": "Now", "jsScript": "return new Date().toISOString();", "outputDataType": "string", "argSpec": {} }
```

## Workflow Variables

Variables are referenced with `$` in Q-Expressions (e.g. `$_row.status`). Which variables exist depends on the kind of workflow.

### Row-Action Variables

| Variable | Description |
|----------|-------------|
| `$_row` | The row that triggered the row-action. Access columns with dot notation: `$_row.status`, `$_row.customer.name` |
| `$_rowMetadata.RowId` | Row reference to the triggering row (typed as a row reference to the sheet, so it can be passed to `patchSheetRowByRowRef`) |
| `$_rowMetadata.SheetNameId` | nameId of the sheet the row-action is attached to |
| `$_oldRow` | **OnSheetRowUpdated**: the row's values *before* the change. **OnSheetRowDeleted**: the values of the deleted row |
| `$<parameterNameId>` | **OnDemand** only: the values of the row-action's parameters, entered by the user when running it |

On **OnSheetRowDeleted**, the row no longer exists, so `$_row` is empty — read the deleted values from `$_oldRow`.

### Timing Action Variables
Timing actions are not tied to a row; they only receive the shared variables below.

### Webhook Variables
| Variable | Description |
|----------|-------------|
| `$_body` | The JSON body of the incoming webhook request, e.g. `$_body.order.id` |

### Procedure Variables
A procedure only sees its own declared parameters (`$<parameterNameId>`) plus the shared variables below. It does **not** see the caller's variables such as `$_row`; pass what it needs as parameters.

### Shared Variables (all workflow kinds)
| Variable | Description |
|----------|-------------|
| `$_f_<fieldNameId>` | Value of a workbook field, e.g. `$_f_taxRate` |
| `$_SECRET_<secretNameId>` | Decrypted value of a workbook secret, e.g. `$_SECRET_stripeKey`. Never write a secret into sheet data or notification messages |
| `$ActingMember` | The member on whose behalf the workflow runs, with `.IdpSub`, `.Name`, `.Email`, `.Role`, `.ClientId`. Empty when nobody triggered it (timing actions, webhooks) |
| `$<outputVarName>` | Any variable created by an earlier instruction's `outputVarName` (or `iteratorVarName`, `responseHeaderVarName`, `statusCodeVarName`) |

Variable names you declare must start with a letter and contain only letters, digits and underscores.

## Row-Agnostic vs Row-Aware Expressions

Each Q-Expression parameter is evaluated in one of two contexts:

- **Row-Agnostic**: evaluated once, with no current row. Only `$variables`, literals and functions are allowed — `@column` references are **not** available.
- **Row-Aware**: evaluated against a specific row of a sheet. `@column` refers to a column of *that* row, and `$variables` are still available.

`$_row.column` is a variable, so it works everywhere. `@column` only works in Row-Aware parameters, and refers to the row the instruction is currently working on — not necessarily the row that triggered the row-action.

```yaml
execInstructions:
# Row-Aware filter: @customerId is a column of each 'orders' row being tested;
# $_row.customerId is the customer of the row that triggered the row-action
- type: querySheet
  queryingSheetNameId: "orders"
  filterQPredicate: "@customerId = $_row.customerId AND @status = 'open'"
  outputVarName: "openOrders"

# Row-Agnostic: no @column allowed
- type: runQExpression
  qExpression: "CountList($openOrders)"
  outputVarName: "openOrderCount"
```

The context of each parameter is listed in the instruction reference below.

## Instruction Reference

### 1. querySheet
Query rows from a sheet and store them as a list.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `queryingSheetNameId` | — | yes | Sheet to query |
| `filterQPredicate` | Row-Aware (rows of the queried sheet) | yes | Filter condition |
| `outputVarName` | — | yes | Variable that receives the list of matching rows |

```yaml
- type: querySheet
  queryingSheetNameId: "orders"
  filterQPredicate: "@status = 'pending' AND @amount > 1000"
  outputVarName: "pendingHighValueOrders"
```

### 2. runQExpression
Evaluate a Q-Expression and store the result.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `qExpression` | Row-Agnostic | yes | Expression to evaluate |
| `outputVarName` | — | yes | Variable that receives the result |

```yaml
- type: runQExpression
  qExpression: "$_row.quantity * $_row.unitPrice * (1 + $_f_taxRate)"
  outputVarName: "totalWithTax"
```

### 3. runQExpressionWithRowRefContext
Load a single row through a row reference, then evaluate an expression against it.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `rowRefGetterQExpression` | Row-Agnostic | yes | Must return a **row reference** (e.g. a RowRef column value, `$_rowMetadata.RowId`, or a sheet-row parameter) |
| `qExpression` | Row-Aware (the referenced row) | yes | Expression evaluated against the referenced row |
| `outputVarName` | — | yes | Variable that receives the result |

```yaml
- type: runQExpressionWithRowRefContext
  rowRefGetterQExpression: "$_row.customer"      # customer is a RowRef column
  qExpression: "@name + ' <' + @email + '>'"     # columns of the customer row
  outputVarName: "customerContact"
```

### 4. patchSheetRow
Update every row of a sheet that matches a condition.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `targetSheetNameId` | — | yes | Sheet to update |
| `selectTargetQPredicate` | Row-Aware (rows of the target sheet) | yes | Selects the rows to update |
| `patchColumnByQExpressionDef` | **Row-Agnostic** | yes | Map of column nameId → expression for the new value |

The new values are evaluated once, without row context, and the same values are written to every matched row. To compute a value from each row's own columns (e.g. `@stock - 1`), use `patchSheetRowByRowId` / `patchSheetRowByRowRef`, or `querySheet` + `iterateCollection`.

```yaml
- type: patchSheetRow
  targetSheetNameId: "orders"
  selectTargetQPredicate: "@customerId = $_row.customerId AND @status = 'draft'"
  patchColumnByQExpressionDef:
    status: "'confirmed'"
    confirmedBy: "$ActingMember.Name"
```

### 5. patchSheetRowByRowRef
Update one row identified by a row reference.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `rowRefGetterQExpression` | Row-Agnostic | yes | Must return a **row reference**; the target sheet is taken from its type |
| `patchColumnByQExpressionDef` | Row-Aware (the target row) | yes | Map of column nameId → expression for the new value |

This is the standard way for a row-action to update **its own triggering row**:

```yaml
- type: patchSheetRowByRowRef
  rowRefGetterQExpression: "$_rowMetadata.RowId"
  patchColumnByQExpressionDef:
    status: "'processed'"
    processedCount: "@processedCount + 1"
```

### 6. patchSheetRowByRowId
Update one row identified by its numeric row ID.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `rowIdGetterQExpression` | Row-Agnostic | yes | Returns the row ID (a number or a row reference) |
| `targetSheetNameId` | — | yes | Sheet containing the row |
| `patchColumnByQExpressionDef` | Row-Aware (the target row) | yes | Map of column nameId → expression for the new value |

```yaml
- type: patchSheetRowByRowId
  rowIdGetterQExpression: "$currentItem.product"
  targetSheetNameId: "products"
  patchColumnByQExpressionDef:
    stockLevel: "@stockLevel - $currentItem.quantity"
```

### 7. addSheetRow
Create a new row.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `targetSheetNameId` | — | yes | Sheet to add the row to |
| `valueSetterQExpressionRecords` | Row-Agnostic | yes | Map of column nameId → expression for the value |

```yaml
- type: addSheetRow
  targetSheetNameId: "audit_log"
  valueSetterQExpressionRecords:
    action: "'order_created'"
    userId: "$ActingMember.IdpSub"
    order: "$_rowMetadata.RowId"
    details: "'Order #' + $_row.orderNumber + ' created'"
```

### 8. upsertSheetRow
Update the rows that match a condition, or create a row if none match.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `targetSheetNameId` | — | yes | Sheet to upsert into |
| `selectTargetQPredicate` | Row-Aware (rows of the target sheet) | yes | Finds existing rows |
| `valueSetterQExpressionRecords` | Row-Aware (each matched row) | yes | Map of column nameId → expression for the value |

When no row matches, a new row is created and `@column` references resolve to blank (0 for numbers, empty for text) — convenient for counters:

```yaml
- type: upsertSheetRow
  targetSheetNameId: "customer_summary"
  selectTargetQPredicate: "@customerId = $_row.customerId"
  valueSetterQExpressionRecords:
    customerId: "$_row.customerId"
    totalOrders: "@totalOrders + 1"
    totalSpent: "@totalSpent + $_row.amount"
```

### 9. execConditionalFlow
Run one of two instruction lists depending on a condition.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `conditionQPredicate` | Row-Agnostic | yes | Boolean condition |
| `caseTrueInstructions` | — | no | Instructions run when the condition is true |
| `caseFalseInstructions` | — | no | Instructions run when the condition is false |

```yaml
- type: execConditionalFlow
  conditionQPredicate: "$_row.amount > 10000"
  caseTrueInstructions:
  - type: patchSheetRowByRowRef
    rowRefGetterQExpression: "$_rowMetadata.RowId"
    patchColumnByQExpressionDef:
      category: "'high-value'"
      requiresApproval: "TRUE"
  caseFalseInstructions:
  - type: patchSheetRowByRowRef
    rowRefGetterQExpression: "$_rowMetadata.RowId"
    patchColumnByQExpressionDef:
      category: "'standard'"
```

### 10. switch
Run the instruction list of the case whose value matches.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `switchValueQExpression` | Row-Agnostic | yes | Value to match; converted to text before matching |
| `cases` | — | no | List of `{ matchValue, instructions }`. `matchValue` is compared to the switch value as exact, case-sensitive text |
| `defaultInstructions` | — | no | Run when no case matches |

```yaml
- type: switch
  switchValueQExpression: "$_row.priority"
  cases:
  - matchValue: "High"
    instructions:
    - type: sendNotification
      messageGetterQText: "Urgent order {{_row.orderNumber}} needs attention"
      severity: "warning"
  - matchValue: "Low"
    instructions:
    - type: patchSheetRowByRowRef
      rowRefGetterQExpression: "$_rowMetadata.RowId"
      patchColumnByQExpressionDef:
        queue: "'backlog'"
  defaultInstructions:
  - type: patchSheetRowByRowRef
    rowRefGetterQExpression: "$_rowMetadata.RowId"
    patchColumnByQExpressionDef:
      queue: "'normal'"
```

### 11. iterateCollection
Loop over a list and run instructions for each item.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `collectionGetterQExpression` | Row-Agnostic | yes | Must return a list (e.g. the output of `querySheet`); null skips the loop |
| `iteratorVarName` | — | yes | Variable holding the current item |
| `iterateInstructions` | — | yes | Instructions run for each item (at least one) |

```yaml
- type: querySheet
  queryingSheetNameId: "order_items"
  filterQPredicate: "@order = $_rowMetadata.RowId"
  outputVarName: "orderItems"

- type: iterateCollection
  collectionGetterQExpression: "$orderItems"
  iteratorVarName: "currentItem"
  iterateInstructions:
  - type: patchSheetRowByRowId
    rowIdGetterQExpression: "$currentItem.product"
    targetSheetNameId: "products"
    patchColumnByQExpressionDef:
      stockLevel: "@stockLevel - $currentItem.quantity"
```

### 12. invokeTemplatedApi
Call an external HTTP API through a workbook **API template** (created on the API Templates page or with `shp api-template create`). Use the template's parameter nameIds as the `templateParameterQExpressionDef` keys: a parameter you don't pass is empty, and an extra key is passed through untyped.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `apiTemplateNameId` | — | yes | nameId of the API template |
| `templateParameterQExpressionDef` | Row-Agnostic | no | Map of template parameter nameId → expression for its value |
| `outputVarName` | — | no | Variable that receives the parsed response body |
| `responseHeaderVarName` | — | no | Variable that receives the response headers (text → text map) |
| `statusCodeVarName` | — | no | Variable that receives the HTTP status code (number) |
| `treatAnyStatusAsSuccess` | — | no (default `false`) | When `true`, a non-2xx status does not fail the workflow — check the status code yourself |

```yaml
- type: invokeTemplatedApi
  apiTemplateNameId: "payment_processor_api"
  templateParameterQExpressionDef:
    amount: "$_row.totalAmount"
    currency: "'USD'"
    orderId: "$_row.orderNumber"
  outputVarName: "paymentResponse"
  statusCodeVarName: "paymentStatus"
  treatAnyStatusAsSuccess: true

- type: execConditionalFlow
  conditionQPredicate: "$paymentStatus >= 400"
  caseTrueInstructions:
  - type: exitRowActionWithMessage
    messageGetterQExpression: "'Payment failed with status ' + $paymentStatus"
    severity: "error"
```

### 13. sendNotification
Send a real-time notification to all members of the workbook. The workflow continues afterwards.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `messageGetterQText` | **Q-Text** template (workflow variables available) | yes | Message text |
| `severity` | — | yes | `info`, `warning` or `error` |

```yaml
- type: sendNotification
  messageGetterQText: "Order {{_row.orderNumber}} shipped. Total: {% q $_row.total %}"
  severity: "info"
```

### 14. exitRowActionWithMessage
Stop the workflow and show a message to the user who ran it. Not allowed inside procedures.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `messageGetterQExpression` | Row-Agnostic | yes | Expression producing the message |
| `severity` | — | yes | `info`, `warning` or `error` (capitalized forms are also accepted) |

```yaml
- type: exitRowActionWithMessage
  messageGetterQExpression: "'Order amount ' + $_row.amount + ' exceeds the credit limit ' + $creditLimit"
  severity: "error"
```

### 15. invokeProcedure
Call a reusable **procedure** (defined on the Procedures page) and optionally capture its output.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `procedureNameId` | — | yes | nameId of the procedure |
| `parameterQExpressionDef` | Row-Agnostic (evaluated in the caller) | no | Map of procedure parameter nameId → expression for its value |
| `outputVarName` | — | no | Variable that receives the value returned by `exitProcedureWithOutput` |

If the procedure ends with `exitProcedureWithOutput` or simply runs to the end, the caller continues. If it fails, the caller fails too.

```yaml
- type: invokeProcedure
  procedureNameId: "calculate_discount"
  parameterQExpressionDef:
    customer: "$_row.customer"
    amount: "$_row.amount"
  outputVarName: "discount"
```

### 16. exitProcedureWithOutput
Return a value from a procedure to its caller. Only allowed inside procedures.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `valueGetterQExpression` | Row-Agnostic | yes | The value to return |

```yaml
# Inside the 'calculate_discount' procedure
- type: exitProcedureWithOutput
  valueGetterQExpression: "If($amount > 1000, $amount * 0.1, 0)"
```

### 17. delay
Pause the workflow for a period of time.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `durationQExpression` | Row-Agnostic | yes | Text duration: ISO 8601 (`'PT30M'`, `'PT2H30M'`, `'P1D'`) or `hh:mm:ss` (`'00:30:00'`) |

```yaml
- type: delay
  durationQExpression: "'PT2H'"
```

### 18. waitForApproval
Ask a member to approve or reject, pause until they respond, then branch.

| Parameter | Context | Required | Description |
|-----------|---------|----------|-------------|
| `approvalRequestMessage` | **Q-Text** template | yes | Message shown to the approver |
| `approverQExpression` | Row-Agnostic | yes | Returns the **IdP subject** (`IdpSub`) of the approving member |
| `timeoutQExpression` | Row-Agnostic | no (default `'P7D'`) | ISO 8601 duration to wait. If it expires, the workflow fails |
| `outputVarName` | — | no | Variable that receives `{ _isApproved, comment }` |
| `caseApprovedInstructions` | — | no | Instructions run when approved |
| `caseRejectedInstructions` | — | no | Instructions run when rejected |

The approver receives a notification linking to an approval ticket page, where they approve or reject with an optional comment.

```yaml
- type: waitForApproval
  approvalRequestMessage: "Please approve expense {{_row.title}} for {% q $_row.amount %}"
  approverQExpression: "$_row.manager"   # manager is a Member column; its value is the member's IdpSub
  timeoutQExpression: "'P3D'"
  outputVarName: "decision"
  caseApprovedInstructions:
  - type: patchSheetRowByRowRef
    rowRefGetterQExpression: "$_rowMetadata.RowId"
    patchColumnByQExpressionDef:
      status: "'approved'"
  caseRejectedInstructions:
  - type: patchSheetRowByRowRef
    rowRefGetterQExpression: "$_rowMetadata.RowId"
    patchColumnByQExpressionDef:
      status: "'rejected'"
      rejectionReason: "$decision.comment"
```

## Behavior Notes

- **Permissions are bypassed, validation is not**: rows written by workflows ignore the sheet's row restriction (`allowRowManipulationQExpression`) and column edit rules (`allowEditQExpression`). Column validation rules and unique constraints still apply: a write that violates them is not saved, and the instruction does not report an error — validate values before writing.
- **Column values in `$_row`**: a RowRef column holds the referenced row's ID (typed as a row reference), and the referenced row's columns are reachable with dot notation (`$_row.customer.name`). A Member column holds the member's IdpSub, plus `.Name` and `.Email`. A SingleSelect/MultiSelect column holds the option ID(s), plus `.Text` for the label.
- **Writes raise row events**: rows created, updated or deleted by a workflow trigger the sheet's row-actions like any other change. An `OnSheetRowUpdated` row-action that patches its own row can therefore trigger itself again — use an update fire condition (see [Row-Action docs](sheetyapp-row-action.md)) or a guard condition to avoid loops.
- **Strict typing**: Q-Expression does not convert types implicitly (except `+` with text, which concatenates). Comparing a number with text, or using `>` on text, is an error.

## Complete Examples

### Example 1: Validate and process an order (OnSheetRowCreated)
```yaml
execInstructions:
- type: execConditionalFlow
  conditionQPredicate: "IsBlank($_row.customer) OR $_row.total <= 0"
  caseTrueInstructions:
  - type: exitRowActionWithMessage
    messageGetterQExpression: "'Order is missing a customer or has an invalid total'"
    severity: "error"

- type: patchSheetRowByRowRef
  rowRefGetterQExpression: "$_rowMetadata.RowId"
  patchColumnByQExpressionDef:
    status: "'pending'"

- type: execConditionalFlow
  conditionQPredicate: "$_row.total > 1000"
  caseTrueInstructions:
  - type: addSheetRow
    targetSheetNameId: "high_value_orders"
    valueSetterQExpressionRecords:
      order: "$_rowMetadata.RowId"
      amount: "$_row.total"
```

### Example 2: Complete an order when all items are shipped (OnSheetRowUpdated on order_items)
```yaml
execInstructions:
- type: querySheet
  queryingSheetNameId: "order_items"
  filterQPredicate: "@order = $_row.order AND @status != 'shipped'"
  outputVarName: "unshippedItems"

- type: execConditionalFlow
  conditionQPredicate: "CountList($unshippedItems) = 0"
  caseTrueInstructions:
  - type: patchSheetRowByRowRef
    rowRefGetterQExpression: "$_row.order"
    patchColumnByQExpressionDef:
      status: "'completed'"
  - type: sendNotification
    messageGetterQText: "Order {% q $_row.order %} is fully shipped"
    severity: "info"
```

### Example 3: Send an order to a fulfillment system (OnDemand)
```yaml
execInstructions:
- type: invokeTemplatedApi
  apiTemplateNameId: "orders_fulfillment_api"
  templateParameterQExpressionDef:
    orderNumber: "$_row.orderNumber"
    totalAmount: "$_row.totalAmount"
  outputVarName: "fulfillmentResponse"

- type: patchSheetRowByRowRef
  rowRefGetterQExpression: "$_rowMetadata.RowId"
  patchColumnByQExpressionDef:
    fulfillmentId: "$fulfillmentResponse.id"
    sentToFulfillment: "TRUE"
```

### Example 4: Reorder stock with a reminder (OnSheetRowUpdated on products)
```yaml
execInstructions:
- type: execConditionalFlow
  conditionQPredicate: "$_row.stockLevel <= $_row.reorderPoint AND $_oldRow.stockLevel > $_oldRow.reorderPoint"
  caseTrueInstructions:
  - type: addSheetRow
    targetSheetNameId: "purchase_orders"
    valueSetterQExpressionRecords:
      product: "$_rowMetadata.RowId"
      quantityToOrder: "$_row.reorderQuantity"
      status: "'pending'"
  - type: delay
    durationQExpression: "'P1D'"
  - type: sendNotification
    messageGetterQText: "Reminder: purchase order for {{_row.name}} is still pending"
    severity: "warning"
```

### Example 5: Record incoming webhook data (Webhook)
```yaml
execInstructions:
- type: upsertSheetRow
  targetSheetNameId: "payments"
  selectTargetQPredicate: "@externalId = $_body.payment.id"
  valueSetterQExpressionRecords:
    externalId: "$_body.payment.id"
    amount: "$_body.payment.amount"
    status: "$_body.payment.status"
```

## YAML Best Practices

- **Quote every expression** in double quotes, and string literals inside it in single quotes: `"'pending'"`.
- **Indent consistently** (2 spaces). Nested instruction lists (`caseTrueInstructions`, `instructions`, `iterateInstructions`, …) are YAML lists.
- **Fail early**: validate input with `execConditionalFlow` + `exitRowActionWithMessage` before writing any data.
- **Query once, reuse**: store `querySheet` results in a variable instead of querying repeatedly.
- **Reuse logic with procedures**: move steps shared by several workflows into a procedure and call it with `invokeProcedure`.
- **Keep secrets in secrets**: reference credentials as `$_SECRET_<nameId>` (or inside API template headers), never as literals in YAML.
- **Use `description`** on non-obvious steps; it shows up in execution logs.
