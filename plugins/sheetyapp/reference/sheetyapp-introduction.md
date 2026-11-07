# SheetyApp Product Description

SheetyApp is a collaborative data management platform that helps teams organize, visualize, and automate their structured data. Think of it as a powerful alternative to traditional spreadsheets, with advanced features for collaboration, automation, and customization.

## Core Capabilities

1. **Smart Workbooks & Sheets**
   - Create workbooks to organize your team's data
   - Design structured sheets with typed columns (text, numbers, dates, selections, members, references to other sheets, computed values)
   - Link sheets through row references and sheet associations
   - Enforce data quality with validation rules and unique constraints
   - Import rows from spreadsheet files

2. **Team Collaboration**
   - Invite members with roles: Owner, Admin, Contributor, SheetWriter, SheetReader
   - Accept people through registration requests, optionally auto-approved by a rule
   - Work together on the same data in real time
   - Restrict who can change rows and columns with Q-Expression rules

3. **Powerful Automation**
   - **Row-actions**: workflows that run when rows are created, updated or deleted, or on demand with user input
   - **Timing actions**: workflows that run on a recurring schedule or at dates taken from your data
   - **Procedures**: reusable workflow steps with parameters and return values
   - **Webhooks**: endpoints that let external systems start workflows
   - Workflow steps for querying and changing data, branching, loops, API calls, notifications, delays and approvals

4. **Integrations**
   - **API templates**: reusable, parameterized HTTP calls to external systems
   - **Secrets**: securely stored API keys and tokens for those calls
   - **Row triggers**: call API templates from the row form to look up or suggest values

5. **Custom Views & Apps**
   - Saved queries that filter and reshape sheet data
   - Workbook apps: dashboards built from widgets (grids, bar/line/pie charts, Gantt charts, heat maps, Q-Text, parameter inputs)
   - Publish apps to share them

6. **Advanced Formula System (Q-Expression)**
   - A formula language similar to Excel, working on named columns and related sheets
   - Computed columns that update automatically
   - Q-functions: custom functions written in JavaScript
   - Filters, validation, permission rules and workflow logic all use the same language
   - Q-Text templates for dynamic messages, URLs and payloads

7. **Monitoring**
   - Every workflow run is recorded with a step-by-step execution log
   - In-app notifications for workflow messages and approval requests

## Key Benefits

- **Flexibility**: More structured and powerful than spreadsheets, but more user-friendly than databases
- **Efficiency**: Automate repetitive tasks with row-actions, timing actions and webhooks
- **Collaboration**: Real-time teamwork with role-based access controls
- **Customization**: Design exactly the right solution for your unique data needs
- **Scalability**: Start simple and add complexity as your needs grow
- **Programmability**: Extend functionality with q-functions while keeping a familiar Excel-like formula experience

## Excel vs. SheetyApp

While Excel is excellent for individual data analysis, SheetyApp offers advantages for team data management:

| Feature | Excel | SheetyApp |
|---------|-------|-----------|
| Formulas | Cell-based formulas | Column-based formulas with cross-sheet lookups and references |
| Custom Functions | VBA macros | Q-functions in JavaScript |
| Collaboration | File sharing | Real-time collaboration with roles and permission rules |
| Data Structure | Flat tables | Related sheets with database-like capabilities |
| Automation | Macros | Event-driven, scheduled and webhook workflows with approvals |
| Extensibility | VBA or Office Add-ins | Q-functions, API templates and webhooks |

## Use Cases

SheetyApp helps teams manage:
- Project tracking and task management
- Customer and contact information
- Inventory and asset tracking
- Application processes and approvals
- Custom business processes
- And much more!

# Guide to Understanding SheetyApp Workbook Definition Snapshots

A workbook definition snapshot is a JSON representation of a SheetyApp workbook: its structure, configuration and custom functionality. This guide explains each section of the snapshot.

## Workbook Definition Snapshots Overview

```
{
  "workbookName": "...",                        // Name of the workbook
  "workbookDescription": "...",                 // Description of the workbook's purpose
  "sheets": [ ... ],                            // Sheets (data tables) and their columns
  "sheetAssociations": [ ... ],                 // Summaries of related rows shown on a sheet
  "queryViews": [ ... ],                        // Saved queries
  "qFunctions": { ... },                        // Q-functions (custom JavaScript functions)
  "fields": [ ... ],                            // Workbook-level values
  "apiTemplates": [ ... ],                      // Reusable external HTTP calls
  "secrets": [ ... ],                           // Secret metadata (values are never included)
  "rowActions": { ... },                        // Row-actions, grouped by sheet ID
  "timingActions": [ ... ],                     // Scheduled and recurring workflows
  "procedures": [ ... ],                        // Reusable workflow procedures
  "webhooks": [ ... ],                          // Incoming webhook workflows
  "rowTriggers": { ... },                       // Row-form API triggers, grouped by sheet ID
  "workbookApps": [ ... ],                      // Dashboards built from widgets
  "rowFormInfoConfigs": { ... },                // Row form info panel configuration, by sheet ID
  "sheetRowFieldColumnOrderConfigs": { ... },   // Row form field ordering, by sheet ID
  "rowAssociationInfoConfigs": { ... },         // Associated-row display configuration, by sheet ID
  "rows": { ... }                               // Optional: row data, grouped by sheet ID
}
```

Sections keyed by sheet ID (`"1": [...]`) use the numeric `id` of a sheet from `sheets`.

## Key Components in Detail

### 1. Sheets

Sheets are the data tables of a workbook:

```json
"sheets": [
  {
    "id": 1,
    "name": "Orders",
    "nameId": "orders",
    "description": "Customer orders",
    "columns": { ... },
    "representativeColumn": "orderNumber",
    "uniqueColumnNameId": "orderNumber",
    "allowRowManipulationQExpression": "$ActingMember.Role != 'SheetReader'",
    "appearAtSubMenu": true
  }
]
```

- `nameId` is the identifier used in Q-Expressions, YAML instructions and URLs
- `representativeColumn` is the column used to display a row when it is referenced from elsewhere
- `allowRowManipulationQExpression` is a Q-Expression deciding whether the acting member may change a row

### 2. Column Definitions

```json
"columns": {
  "orderNumber": {
    "name": "Order Number",
    "nameId": "orderNumber",
    "description": "Human-readable order number",
    "dataType": "String",
    "validationRules": [ ... ],
    "fieldSuggestionConfig": { ... },
    "allowEditQExpression": "Expression controlling editability",
    "textDisplayVariant": "..."
  },
  "customer": { "name": "Customer", "nameId": "customer", "dataType": "RowRef", "rowRefSheetId": 2 },
  "status": { "name": "Status", "nameId": "status", "dataType": "SingleSelect", "selectOptions": { "1": "Open", "2": "Closed" } },
  "total": { "name": "Total", "nameId": "total", "dataType": "Compute", "computeColumnQlangExpression": "@quantity * @unitPrice", "computeQExpressionDataType": "number" }
}
```

Column data types:
- Basic: `String`, `Number`, `Boolean`, `DateTime`
- References: `RowRef` (one row of another sheet, `rowRefSheetId`), `MultiRowRef` (several rows)
- People: `Member` (a workbook member)
- Selections: `SingleSelect`, `MultiSelect` (options in `selectOptions`, keyed by option ID)
- Special: `SealedSingleSelect` (a selection that cannot be changed once made, recording its author), `SingleVote`
- Computed: `Compute` (value from `computeColumnQlangExpression`, result type in `computeQExpressionDataType`)

### 3. Sheet Associations

Sheet associations show a summary of the rows of another sheet that reference a row:

```json
"sheetAssociations": [
  {
    "uniqueId": "guid",
    "name": "Order Count",
    "sheetId": 2,
    "refSheetId": 1,
    "refSheetColumnNameId": "customer",
    "isActive": true,
    "evaluationQText": "total: {% q CountList($_associatedRows) %}"
  }
]
```

Here, each customer row (sheet 2) shows a summary of the orders (sheet 1) whose `customer` column points to it.

### 4. Query Views

```json
"queryViews": [
  {
    "id": "uuid",
    "name": "Open Orders",
    "targetSheetId": 1,
    "filterQPredicate": "@status.Text = 'Open'",
    "selectColumns": [ "orderNumber", "customer" ],
    "selectQExpression": {
      "lineTotal": { "qExpression": "@quantity * @unitPrice", "columnName": "Line Total", "computeDataType": "number" }
    }
  }
]
```

- Queries filter a sheet with a Q-Expression and choose the columns to return
- `selectQExpression` adds computed columns to the result
- Queries feed app widgets, app references and scheduled timing actions

### 5. Q-Functions

```json
"qFunctions": {
  "formatCurrency": {
    "name": "formatCurrency",
    "jsScript": "return '$' + amount.toFixed(2);",
    "outputDataType": "string",
    "argSpec": { "amount": "number" },
    "isTypeConversionFunction": false,
    "disableMode": null
  }
}
```

- `jsScript` is a JavaScript function body; arguments are available by their `argSpec` names
- Q-functions are called from any Q-Expression: `formatCurrency(@total)`

### 6. Workbook Fields

Fields store single typed values at workbook level (rather than rows in a sheet):

```json
"fields": [
  { "nameId": "taxRate", "name": "Tax Rate", "datatype": "number", "value": 0.08 }
]
```

- A field's `datatype` can be a basic type (`string`, `number`, `boolean`, `datetime`) or a reference to a row (`srr.<sheetNameId>`) or a list of rows (`_s.srr.<sheetNameId>`)
- Fields are referenced as `$_f_<nameId>` (e.g. `$_f_taxRate`) in workflows and workbook apps

### 7. API Templates

Reusable definitions of external HTTP calls:

```json
"apiTemplates": [
  {
    "nameId": "createInvoice",
    "name": "Create Invoice",
    "urlQText": "https://api.example.com/customers/{{customerId}}/invoices",
    "jsonPayloadQText": "{ \"amount\": {% q $amount %} }",
    "headerQTexts": { "Authorization": "Bearer {% q $_SECRET_billingKey %}" },
    "apiVerb": "Post",
    "parameters": [
      { "nameId": "customerId", "dataType": "string" },
      { "nameId": "amount", "dataType": "number" }
    ]
  }
]
```

- URL, payload and headers are Q-Text templates over the template's `parameters`
- `apiVerb`: `Get`, `Post`, `Put`, `Patch` or `Delete`
- Called from workflows with `invokeTemplatedApi`, and from the row form through row triggers

### 8. Secrets

```json
"secrets": [
  { "uniqueId": "guid", "nameId": "billingKey", "description": "Billing API key", "type": "Simple" }
]
```

- Only metadata is included; secret values are never part of the snapshot
- `type`: `Simple` (a stored value) or `MicrosoftGraphAccessToken` (an OAuth token obtained through Microsoft sign-in)
- Referenced as `$_SECRET_<nameId>` in API templates and workflows

### 9. Row-Actions

```json
"rowActions": {
  "1": [
    {
      "triggerType": "OnSheetRowUpdated",
      "uniqueId": "guid",
      "sheetId": 1,
      "name": "Notify on Shipment",
      "disabled": false,
      "yamlInstructions": "execInstructions:\n- type: sendNotification\n  ...",
      "updateFireCondition": { "groups": [ { "fieldConditions": [ { "fieldNameId": "status", "expectedValue": { "value": "2" } } ] } ] }
    }
  ]
}
```

- `triggerType`: `OnSheetRowCreated`, `OnSheetRowUpdated`, `OnSheetRowDeleted` or `OnDemand`
- Automatic triggers can have a fire condition (`createFireCondition`, `updateFireCondition`, `deleteFireCondition`)
- `OnDemand` row-actions can have `enabledQExpression` and `parameterDefinitions`
- `yamlInstructions` follows the [YAML Instruction Reference](sheetyapp-row-action-yaml-instruction.md); see also [Row-Actions](sheetyapp-row-action.md)

### 10. Timing Actions, Procedures and Webhooks

```json
"timingActions": [
  { "$type": "Recurring", "id": "guid", "description": "Nightly cleanup", "cronExpression": "0 2 * * *", "yamlInstructions": "...", "disabled": false },
  { "$type": "Scheduled", "id": "guid", "description": "Due date reminder", "pointInTimeSelector": { "sheetQueryId": "guid", "columnNameId": "dueDate" }, "yamlInstructions": "...", "disabled": false }
],
"procedures": [
  { "uniqueId": "guid", "name": "Calculate Discount", "nameId": "calculate_discount", "parameterDefinitions": [ { "nameId": "amount", "datatype": "number" } ], "yamlInstructions": "..." }
],
"webhooks": [
  { "workbookId": 123, "webhookId": "guid", "description": "Payment events", "isDisabled": false, "yamlInstructions": "..." }
]
```

- Timing actions run on a cron schedule (`Recurring`) or at the date/time values of a saved query's column (`Scheduled`)
- Procedures are called from other workflows with `invokeProcedure`
- Webhooks run their instructions when an external system calls them; the request body is `$_body`

### 11. Row Triggers

```json
"rowTriggers": {
  "1": [
    { "uniqueId": "guid", "name": "Lookup Address", "nameId": "lookupAddress", "apiTemplateNameId": "addressLookup", "parameterColumnAccessExp": { "postcode": "postcode" } }
  ]
}
```

- Link an API template to a sheet's row form; `parameterColumnAccessExp` maps template parameters to columns
- While a row is being edited, a change to a mapped column calls the API template; the result is shown in the info panel and can feed value suggestions

### 12. Workbook Apps

```json
"workbookApps": [
  {
    "id": "uuid",
    "name": "Sales Dashboard",
    "globalUniqueAlias": "sales-dashboard",
    "references": [ { "nameId": "openOrders", "name": "Open Orders", "referenceType": "SheetQuery", "sheetId": 1, "queryId": "guid" } ],
    "parameters": [ { "nameId": "region", "name": "Region", "dataType": "string", "defaultValue": "EU" } ],
    "computeReferences": [ { "nameId": "openCount", "name": "Open Count", "dataType": "number", "qExpression": "CountList($_ref_openOrders)" } ],
    "widgetDefinitions": [
      {
        "id": "uuid",
        "contentDefinition": {
          "widgetType": "SheetQueryBarChart",
          "sheetId": 1,
          "queryId": "queryId"
          // Additional widget-specific configuration
        },
        "layoutPosition": { "xAxis": 0, "yAxis": 0, "width": 6, "height": 15 }
      }
    ]
  }
]
```

- **References** bring data into the app: rows of a sheet with an optional filter (`SheetRows`) or a saved query (`SheetQuery`). Referenced as `$_ref_<nameId>`
- **Parameters** are inputs the viewer can change (with `ParameterInput` widgets). Referenced as `$_par_<nameId>`
- **Compute references** are values calculated from Q-Expressions. Referenced as `$_cref_<nameId>`
- Widget types: `SheetQueryGrid`, `SheetQueryBarChart`, `SheetQueryLineChart`, `SheetQueryPieChart`, `SheetQueryGanttChart`, `SheetQueryHeatMap`, `QTextWidget`, `ParameterInput`
- `layoutPosition` places the widget on the dashboard grid

## Common Patterns in Workbook Definition Snapshots

1. **Data Validation**: Q-Expressions in `validationRules` enforce data integrity
2. **Computed Columns**: Formulas in `computeColumnQlangExpression` calculate values
3. **Permission Control**: `allowRowManipulationQExpression` and `allowEditQExpression` manage who can change data
4. **Event Automation**: `rowActions` react to row changes or run on demand
5. **Scheduled Automation**: `timingActions` run on a schedule or at dates from your data
6. **Reusable Logic**: `procedures` hold steps shared by several workflows; `qFunctions` hold shared calculations
7. **Integration**: `apiTemplates` with `secrets` call external systems; `webhooks` receive calls from them
8. **Dashboards**: `workbookApps` combine references, parameters and widgets
9. **Shared Values**: `fields` hold workbook-level values reused across workflows and apps

## How to Analyze a Snapshot

To understand what a workbook does before explaining, modifying or extending it:

1. Identify the core sheets and how they relate (RowRef columns, `sheetAssociations`, lookups in expressions)
2. Review column types, computed columns and validation rules to understand the data model
3. Read the q-functions to understand shared calculations
4. Read row-actions, timing actions, procedures and webhooks to understand the business processes
5. Check API templates and secrets to see which external systems are involved
6. Examine queries and workbook apps to understand the reporting needs
