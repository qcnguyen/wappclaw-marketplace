# Sheetyapp Application Detailed Sitemap

This document lists the navigation routes of the Sheetyapp web application, including URL fragments (hash navigation) for tab-level content.

## Root Routes

| Route | URL Path | Purpose |
|-------|----------|---------|
| Home | `/` | Landing page; lists the workbooks accessible to the current user |
| Workbooks | `/workbooks` | List of all workbooks accessible to the current user |
| Add Workbook | `/workbooks/_add` | Create a new workbook (requires an active subscription) |
| Subscription | `/subscription` | Manage your subscription plan and payments |
| Subscription Enroll | `/subscription/enroll` | Enroll in a subscription plan |
| User Settings | `/settings` | Manage personal user settings and preferences |

## Workbook-Specific Routes

All workbook routes follow the pattern `/workbooks/:workbookId/...` where `:workbookId` is the workbook's identifier. Pages marked **Designer** require sheet-design permission (Owner, Admin or Contributor role).

### Workbook Dashboard & Management

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Workbook Home | `/workbooks/:workbookId` | | Workbook dashboard with overview information |
| Workbook Settings | `/workbooks/:workbookId/settings` | | Configure workbook-level settings |
| | | `#profile` | Workbook name and description (Owner only) |
| | | `#connected-apps` | Delegate the workbook to connected apps such as the `shp` CLI, with a role |
| | | `#danger-zone` | Delete the workbook and other destructive operations |
| Secrets | `/workbooks/:workbookId/secrets` | | **Designer.** Manage secrets (API keys, tokens) used by API templates and workflows |
| Notifications | `/workbooks/:workbookId/notifications` | | Notifications sent to you in this workbook, including approval requests |

### Sheet Management

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Sheets List | `/workbooks/:workbookId/sheets` | | All sheets in the workbook |
| Add Sheet | `/workbooks/:workbookId/sheets/_add` | | **Designer.** Create a new sheet |
| View Sheet Rows | `/workbooks/:workbookId/sheets/:sheetNameId` | | View and manage the rows of a sheet |
| View/Edit Row | `/workbooks/:workbookId/sheets/:sheetNameId/rows/:rowId` | | View or edit a single row |
| Sheet Configuration | `/workbooks/:workbookId/sheets/:sheetNameId/config` | | **Designer.** Sheet-level settings |
| | | `#general` | Name, description and other basic properties |
| | | `#constraints` | Unique constraints on columns |
| | | `#row-triggers` | Row triggers: call API templates from the row form when mapped columns change |
| | | `#restriction` | Row access restriction (who may change rows) |
| | | `#field-order` | Preferences: field order and layout of the row form |
| | | `#row-grid` | Row grid display settings |
| Sheet Columns | `/workbooks/:workbookId/sheets/:sheetNameId/columns` | | **Designer.** Design the sheet's columns |

### App Management

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Apps List | `/workbooks/:workbookId/apps` | | All workbook apps |
| Add App | `/workbooks/:workbookId/apps/_add` | | **Designer.** Create a new app |
| View App | `/workbooks/:workbookId/apps/:appId` | | Use an app |
| Edit App | `/workbooks/:workbookId/apps/:appId/edit` | | **Designer.** Edit an app |
| | | `#widgets` | Add and arrange widgets |
| | | `#references` | App references, parameters and compute references |
| | | `#configuration` | App name and other settings |
| Publish App | `/workbooks/:workbookId/apps/:appId/publish` | | **Designer.** Publish the app for sharing |

### User & Membership Management

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Members List | `/workbooks/:workbookId/members` | | All members of the workbook |
| Member Details | `/workbooks/:workbookId/members/:idpSub` | | A member's details and role |
| Registrations | `/workbooks/:workbookId/registrations` | | Manage registration requests (Owner or Admin role) |
| | | `#registrations` | Review and process registration requests |
| | | `#settings` | Registration settings, including the auto-approval rule |

### Row-Actions

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Row-Action List | `/workbooks/:workbookId/row-actions` | | **Designer.** All row-actions in the workbook |
| Add Row-Action | `/workbooks/:workbookId/row-actions/_add` | | **Designer.** Create a row-action |
| Row-Action Details | `/workbooks/:workbookId/row-actions/:rowActionId` | | **Designer.** General settings: name, trigger, fire condition, parameters, restriction (enabled expression / disabled) |
| Row-Action Design | `/workbooks/:workbookId/row-actions/:rowActionId/design` | | **Designer.** Visual flow designer for the row-action's instructions |
| Row-Action Executions | `/workbooks/:workbookId/row-actions/:rowActionId/executions` | | **Designer.** History of runs |
| Row-Action Execution Detail | `/workbooks/:workbookId/row-actions/:rowActionId/executions/:executionId` | | **Designer.** Instruction-by-instruction log of one run |

### Timing Actions

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Timing Action List | `/workbooks/:workbookId/timing-actions` | | **Designer.** All scheduled and recurring actions |
| Add Timing Action | `/workbooks/:workbookId/timing-actions/_add` | | **Designer.** Create a timing action |
| Timing Action Details | `/workbooks/:workbookId/timing-actions/:timingActionId` | | **Designer.** Schedule and general settings |
| Timing Action Design | `/workbooks/:workbookId/timing-actions/:timingActionId/design` | | **Designer.** Visual flow designer |
| Timing Action Executions | `/workbooks/:workbookId/timing-actions/:timingActionId/executions` | | **Designer.** History of runs |
| Timing Action Execution Detail | `/workbooks/:workbookId/timing-actions/:timingActionId/executions/:executionId` | | **Designer.** Log of one run |

### Procedures

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Procedure List | `/workbooks/:workbookId/procedures` | | **Designer.** All reusable procedures |
| Add Procedure | `/workbooks/:workbookId/procedures/_add` | | **Designer.** Create a procedure |
| Edit Procedure | `/workbooks/:workbookId/procedures/:procedureId/edit` | | **Designer.** Edit a procedure |
| | | `#action-designer` | Visual flow designer for the procedure's instructions |
| | | `#general` | Name, nameId and parameters |
| Procedure Executions | `/workbooks/:workbookId/procedures/:procedureId/executions` | | **Designer.** History of runs |
| Procedure Execution Detail | `/workbooks/:workbookId/procedures/:procedureId/executions/:executionId` | | **Designer.** Log of one run |

### Webhooks

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Webhooks | `/workbooks/:workbookId/webhooks` | | **Designer.** All incoming webhooks |
| Webhook Details | `/workbooks/:workbookId/webhooks/:webhookId` | | **Designer.** Webhook URL and settings |
| Webhook Design | `/workbooks/:workbookId/webhooks/:webhookId/design` | | **Designer.** Visual flow designer |
| Webhook Events | `/workbooks/:workbookId/webhooks/:webhookId/events` | | **Designer.** Received requests and their processing |

### Approvals

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Approval Ticket | `/workbooks/:workbookId/approval-tickets/:approvalTicketId` | | Approve or reject a request raised by a workflow's `waitForApproval` step |

### Programming & Integrations

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Q-Functions List | `/workbooks/:workbookId/q-functions` | | **Designer.** All q-functions (custom JavaScript functions) |
| Add Q-Function | `/workbooks/:workbookId/q-functions/_add` | | **Designer.** Create a q-function |
| Edit Q-Function | `/workbooks/:workbookId/q-functions/:functionName/edit` | | **Designer.** Edit a q-function |
| API Templates | `/workbooks/:workbookId/api-templates` | | **Designer.** All API templates (reusable external HTTP calls) |
| Add API Template | `/workbooks/:workbookId/api-templates/_add` | | **Designer.** Create an API template |
| Edit API Template | `/workbooks/:workbookId/api-templates/:apiTemplateNameId/edit` | | **Designer.** Edit an API template |

### Data Analysis & Queries

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Query List | `/workbooks/:workbookId/queries` | | **Designer.** All saved queries |
| Query Details | `/workbooks/:workbookId/queries/:queryId` | | **Designer.** A saved query |
| | | `#result` | Query results in a data grid |
| | | `#definition` | Query definition: target sheet, filter, selected and computed columns |

### Field Management

| Route | URL Path | Tab Fragments | Purpose |
|-------|----------|---------------|---------|
| Fields List | `/workbooks/:workbookId/fields` | | **Designer.** All workbook fields |
| Add Field | `/workbooks/:workbookId/fields/_add` | | **Designer.** Create a workbook field |
| Edit Field | `/workbooks/:workbookId/fields/:fieldNameId/edit` | | **Designer.** Edit a workbook field |

## Tab Fragment Navigation

Pages with tabs record the selected tab in the URL fragment (hash), so you can:

1. Share direct links to specific tabs
2. Return to the same tab when navigating back
3. Bookmark specific views

For example, to open the constraints settings of a sheet:
`/workbooks/abc123/sheets/SampleSheet45/config#constraints`

## URL Parameter Details

- `:workbookId` - The workbook identifier: a hash-id string encoded from the workbook's numeric ID
- `:sheetNameId` - The sheet's nameId (string identifier)
- `:rowId` - The numeric ID of a row
- `:appId` - The GUID of a workbook app
- `:rowActionId` - The GUID of a row-action
- `:timingActionId` - The GUID of a timing action
- `:procedureId` - The GUID of a procedure
- `:webhookId` - The GUID of a webhook
- `:executionId` - The GUID of a workflow execution
- `:approvalTicketId` - The GUID of an approval ticket
- `:functionName` - The name of a q-function
- `:apiTemplateNameId` - The nameId of an API template
- `:queryId` - The GUID of a saved query
- `:idpSub` - The identity provider subject identifier of a member
- `:fieldNameId` - The nameId of a workbook field

## Page Actions

Some pages offer additional actions through header buttons and menus.

### Sheet Rows Page
- **Configurations** - Go to the sheet configuration page
- **Columns** - Go to the sheet columns design page
- **Add Column** - Add a column to the sheet
- **Compute Column** - Add a computed column
- **Import from Spreadsheet** - Import rows from a spreadsheet file
- Run on-demand row-actions on rows from the grid

### Sheet Row Page
- **Edit Row** - Edit the row
- Run on-demand row-actions for the row (only those whose enabled expression is true)
- View associated rows from other sheets and row trigger results in the info panel

### Row-Action / Timing Action / Webhook Detail Pages
- **Design** - Open the visual flow designer
- **Executions** (row-actions, timing actions) / **Events** (webhooks) - Open the run history
