# SheetyApp Row-Action System Documentation

## Overview

Row-actions are SheetyApp's row-level automation. A row-action is attached to a sheet and runs a list of YAML instructions, either automatically when a row is created, updated or deleted, or on demand when a user runs it on a row. Instructions can query and change data, branch on conditions, call external APIs, call procedures, send notifications, wait, and ask for approval.

Row-actions share their YAML instruction language with the other workflow kinds — **timing actions**, **procedures** and **webhooks** — described at the end of this document.

## Table of Contents

- [Row-Action Components](#row-action-components)
- [Trigger Types](#trigger-types)
- [Fire Conditions](#fire-conditions)
- [On-Demand Parameters](#on-demand-parameters)
- [Execution and Monitoring](#execution-and-monitoring)
- [Other Workflow Kinds](#other-workflow-kinds)

## What Row-Actions Are For

- Keep related data in sync when rows change
- Enforce business rules and stop invalid processing with a message
- Integrate with external systems through API templates
- Notify workbook members of important changes
- Run approval processes and time-delayed follow-ups
- Give users one-click operations on a row (with input parameters)

## Row-Action Components

Each row-action consists of:

1. **Name**: a descriptive name
2. **Sheet**: the sheet the row-action is attached to
3. **Trigger Type**: when it runs (see below)
4. **YAML Instructions**: the steps to perform (see the [YAML Instruction Reference](sheetyapp-row-action-yaml-instruction.md))
5. **Disabled**: a switch to turn the row-action off without deleting it
6. **Fire Condition** (automatic triggers only): optional field-value conditions that must hold for it to run
7. **Enabled Q-Expression** (OnDemand only): optional condition controlling whether the row-action is available for a row
8. **Parameter Definitions** (OnDemand only): optional inputs the user fills in when running it

In a workbook snapshot, row-actions appear under `rowActions`, grouped by sheet ID:

```json
"rowActions": {
  "1": [
    {
      "triggerType": "OnDemand",
      "uniqueId": "guid",
      "sheetId": 1,
      "name": "Approve Order",
      "disabled": false,
      "yamlInstructions": "execInstructions:\n- type: ...",
      "enabledQExpression": "@status = 'pending'",
      "parameterDefinitions": [ { "nameId": "note", "datatype": "string" } ]
    }
  ]
}
```

## Trigger Types

| Trigger | Runs when | Extra variables |
|---------|-----------|-----------------|
| `OnSheetRowCreated` | A row is added to the sheet | — |
| `OnSheetRowUpdated` | A row in the sheet is changed | `$_oldRow`: values before the change |
| `OnSheetRowDeleted` | A row is deleted from the sheet | `$_oldRow`: values of the deleted row (`$_row` is empty) |
| `OnDemand` | A user runs it on a specific row | `$<parameterNameId>`: parameter values |

Every row-action also receives `$_row` (the triggering row), `$_rowMetadata.RowId` and `$_rowMetadata.SheetNameId`, plus the shared workflow variables (`$_f_<field>`, `$_SECRET_<secret>`, `$ActingMember`). See [Workflow Variables](sheetyapp-row-action-yaml-instruction.md#workflow-variables).

Use cases:
- **OnSheetRowCreated**: initialize values, create related records, notify the team
- **OnSheetRowUpdated**: react to status changes, update related data, keep audit trails (compare `$_row` with `$_oldRow`)
- **OnSheetRowDeleted**: clean up related data, archive the deleted values
- **OnDemand**: manual approvals, one-time processing, actions that need user input

Define at most one row-action per automatic trigger type on a sheet: for each row event, only one row-action of that trigger type is run. Put several behaviors into one row-action's YAML, or move shared logic into procedures.

Changes made by a workflow raise row events like any other change, so an `OnSheetRowUpdated` row-action that updates its own row can trigger itself again. Use a fire condition or a guard condition to prevent loops.

## Fire Conditions

Automatic row-actions can carry a fire condition so they run only for relevant changes, without writing a guard into the YAML. A fire condition is a set of **groups** of **field conditions**:

- Field conditions in a group are combined with the group's `operator` (`And` / `Or`, default `And`)
- Groups are combined with `groupOperator` (`And` / `Or`, default `And`)
- Values are compared with the stored value, so a **select column takes option IDs** (not labels) and a member column takes the IdpSub

With the CLI, set one with `shp row-action create|update … --fire-field <field>[=<value>|=<from>-><to>]` (simple AND conditions) or `--fire-condition <json>` (the full structure below); `--no-fire-condition` removes it. Field names and option IDs are checked against the sheet first.

### Created / Deleted fire conditions (`createFireCondition`, `deleteFireCondition`)
Each field condition checks the value of a field (on the new row for Created, on the deleted row for Deleted):
- `fieldNameId`: the column to check
- `expectedValue` omitted: the field must have a (non-null) value
- `expectedValue: { "value": X }`: the field must equal X (`null` allowed)
- `expectedValue: { "value": X, "isNegated": true }`: the field must **not** equal X

```json
"createFireCondition": {
  "groups": [
    { "fieldConditions": [ { "fieldNameId": "priority", "expectedValue": { "value": "high" } } ] }
  ]
}
```

### Updated fire condition (`updateFireCondition`)
Each field condition looks at how a field changed:
- `fieldNameId`: the column to check
- Only `fieldNameId`: fires when the field's value changed
- `fromValue: { "value": X }`: the field changed *from* X
- `expectedValue: { "value": Y }`: the field changed *to* Y
- `isNegated: true` on either matcher inverts that comparison

```json
"updateFireCondition": {
  "groups": [
    {
      "fieldConditions": [
        { "fieldNameId": "status", "fromValue": { "value": "draft" }, "expectedValue": { "value": "submitted" } }
      ]
    }
  ]
}
```

## On-Demand Parameters

On-demand row-actions can declare parameters. When a user runs the row-action, they are asked for values, which the YAML reads as `$<parameterNameId>`.

Each parameter has a `nameId`, a `datatype` and optional `predefinedOptions` (a list of allowed values). Supported datatypes:
- `string`, `number`, `boolean`, `datetime`
- A row of a sheet (`srr.<sheetNameId>`): the user picks a row; the variable holds that row with its columns (`$customer.email`) and can be used as a row reference
- A list of rows of a sheet (`_s.srr.<sheetNameId>`): the user picks several rows; the variable is a list
- A select column's options (`css.<sheetNameId>.<columnNameId>` single, `cms.<sheetNameId>.<columnNameId>` multiple): the user picks from that column's options

The **Enabled Q-Expression** is evaluated against the row (Row-Aware, `@column` allowed). When it is false, the row-action is not offered for that row:

```
@status = 'pending' AND $ActingMember.Role = 'Admin'
```

## Execution and Monitoring

- Row-actions run in the background. Long-running steps (`delay`, `waitForApproval`) pause the execution without blocking anything else.
- Each run is recorded as an **execution** with a log of every instruction, its result, branches taken and errors. Open it from the row-action's **Executions** page.
- When a run ends with `exitRowActionWithMessage`, the message is shown to the user with the chosen severity.
- `sendNotification` messages and approval requests appear in the workbook's **Notifications**; approvers respond on the approval ticket page.

## Other Workflow Kinds

All of these use the same [YAML instruction language](sheetyapp-row-action-yaml-instruction.md).

### Timing Actions
Workbook-level workflows that run on a schedule rather than on a row event. They receive only the shared variables (fields, secrets).
- **Recurring**: runs on a cron schedule (`cronExpression`)
- **Scheduled**: runs at points in time taken from data — a saved query plus one of its date/time columns (`pointInTimeSelector: { sheetQueryId, columnNameId }`); each row's date/time is a scheduled run

### Procedures
Reusable instruction lists with a `nameId` and typed parameters (same datatypes as on-demand parameters). They are called from any workflow with `invokeProcedure`, can return a value with `exitProcedureWithOutput`, and only see their own parameters plus the shared variables. `exitRowActionWithMessage` is not allowed inside a procedure.

### Webhooks
Workbook endpoints that external systems call. Each webhook has its own URL and YAML instructions; the request's JSON body is available as `$_body`. Received requests are listed on the webhook's **Events** page. The URL (`<API>/webhook-triggers/<webhookId>`) accepts an anonymous POST, so treat it as a secret and validate `$_body` before writing data. Managed with `shp webhook` (create, update, `run` with a test payload, `events`).

### Row Triggers (sheet configuration)
Row triggers are not workflows. A sheet's **Row Triggers** settings link an API template to the row form: template parameters are mapped from the row's columns, and while a user is editing a row, a change to a mapped column calls the API template. The response is shown in the row's info panel and can feed column value suggestions. Use a row-action with `invokeTemplatedApi` to call an API when a row is actually saved.
