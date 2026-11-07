# Understanding and Using Q-Text

Q-Text is SheetyApp's templating language. It creates dynamic text by combining regular text with values from the current context, similar to mail merge but more powerful. Q-Text is built on the [Liquid template language](https://liquidjs.com/tutorials/intro-to-liquid.html) and adds a `{% q %}` tag for evaluating [Q-Expressions](sheetyapp-q-expression.md).

## Where Q-Text Is Used

| Where | What you can reference |
|-------|------------------------|
| **API templates** (URL, JSON payload, headers) | The template's parameters (`{{paramName}}`, `$paramName`), secrets (`$_SECRET_<nameId>`), `$ActingMember` |
| **Workflow `sendNotification`** (`messageGetterQText`) | All workflow variables: `{{_row.orderNumber}}`, `{% q $_row.total * 2 %}`, `$_f_<field>`, outputs of earlier instructions |
| **Workflow `waitForApproval`** (`approvalRequestMessage`) | All workflow variables, as above |
| **Sheet associations** (evaluation template) | `$_associatedRows` (the associated rows), e.g. `{% q CountList($_associatedRows) %}` |
| **Q-Text widgets** in workbook apps | App variables: `$_ref_<reference>`, `$_par_<parameter>`, `$_cref_<computeReference>`, `$_f_<field>` |

What a name refers to depends on the context: in a workflow, `{{_row.customerName}}` reads the triggering row's `customerName` column; in an API template, `{{customerName}}` reads the template parameter named `customerName`.

## What Can You Do with Q-Text?

- Build URLs, JSON payloads and headers for API calls from workflow data
- Write personalized notification and approval messages
- Show dynamic labels and summaries in workbook apps
- Summarize associated rows (counts, totals) on a sheet

## Basic Syntax - The Building Blocks

### 1. Regular Text
Normal text appears exactly as written:
```
Hello there! This is regular text.
```

### 2. Variables
Use `{{name}}` to insert a value from the context, without a `$` prefix:
```
Hello {{firstName}}, your order number is {{orderNumber}}.
```
Use dot notation for a column of a variable: `{{_row.orderNumber}}`.

For values reached *through* a column — a referenced row's columns (`customer.email`), a member's `.Name`/`.Email`, a select column's `.Text` — or for webhook body data, use `{% q %}` instead: `{% q $_row.customer.email %}`, `{% q $_body.order.id %}`. Q-Expression resolves these paths; plain `{{ }}` may render them empty.

### 3. Q-Expression Calculations
Use `{% q expression %}` to evaluate a Q-Expression and insert its result. Inside the tag, use normal Q-Expression syntax: `$` for variables, single quotes for text, functions, and so on.
```
Your total is ${% q $quantity * $price %}.
```

The `q` filter does the same for an expression held in a string: `{{ '$quantity * $price' | q }}`.

**Important**: in Liquid syntax, use the variable name directly (`{{ firstName }}`); inside `{% q %}`, prefix it with `$` (`{% q $firstName %}`):

```liquid
Customer Tier: {{ customerTier }}                    <!-- Liquid syntax -->
Discount: {% q If($customerTier = 'VIP', 10, 5) %}   <!-- Q-Expression syntax -->
```

## Liquid Features

Because Q-Text is Liquid, all standard Liquid features work alongside `{% q %}`:

- **Filters**: transform values, e.g. `| upcase`, `| date`, `| default`
- **Control flow**: `{% if %}`, `{% unless %}`, `{% case %}`
- **Loops**: `{% for item in items %}`
- **Escaping**: `{% raw %}...{% endraw %}` to output Liquid syntax literally

```liquid
Hello {{ firstName | upcase }},

{% if orderTotal > 100 %}
  You qualify for free shipping!
{% else %}
  Add ${{ 100 | minus: orderTotal }} more for free shipping.
{% endif %}

Your order total: ${% q $orderTotal %}
```

## Practical Examples

### Notification from a Row-Action
```
Order {{_row.orderNumber}} was shipped to {% q $_row.customer.name %}.
Total: ${% q Round($_row.total, 2) %}
```

### Approval Request
```
{% q $_row.requester.Name %} requests approval for "{{_row.title}}" ({% q $_row.amount %} USD).
```

### Dynamic API URL (API template with parameters `customerId` and `orderId`)
```
https://api.service.com/customers/{{customerId}}/orders/{{orderId}}
```
**Result:** `https://api.service.com/customers/12345/orders/67890`

### API Authorization Header (using a secret)
```
Bearer {% q $_SECRET_serviceApiKey %}
```

### JSON Payload (API template)
```
{
  "orderId": "{{orderId}}",
  "amount": {% q $amount %},
  "priority": "{% q If($amount > 1000, 'high', 'normal') %}"
}
```

### Conditional Message
```
Dear {% q If($_row.membershipLevel = 'Premium', 'Valued', 'Esteemed') %} Customer,

Your order total is ${% q $_row.orderTotal %}.
{% q If($_row.orderTotal > 100, 'You qualify for free shipping.', 'Add $' + ToString(100 - $_row.orderTotal) + ' more for free shipping.') %}
```

### Association Summary
```
{% q CountList($_associatedRows) %} related orders
```

### Looking Up Data from Other Sheets
Use the Q-Expression lookup syntax inside `{% q %}`:
```
Assigned Manager: {% q $_row.customerId:staff@customerId:managerName %}
```

### Current Member
```
Updated by: {% q $ActingMember.Name %} ({% q $ActingMember.Email %})
```

## Tips for Success

1. **Start simple**: begin with text and variables, then add calculations
2. **Know your context**: check which variables exist where the template runs (see the table above)
3. **Use `{% q %}` for any logic or math**, and `{{ }}` for plain values
4. **Quote text inside expressions** with single quotes: `{% q If($status = 'Active', 'Yes', 'No') %}`
5. **Never put secret values into notifications or sheet data**; use secrets only in API templates and API calls

## Troubleshooting Common Issues

**Nothing appears for a value**
- Check the name exists in this context (e.g. `{{_row.status}}` in workflows, not `{{status}}`)
- For referenced-row columns, member `.Name`/`.Email` or select `.Text`, use `{% q $_row.customer.name %}` rather than `{{ }}`
- Names are case-sensitive and must match the column, parameter or variable nameId exactly

**A calculation fails**
- Inside `{% q %}`, variables need `$`: `{% q $price * $quantity %}`
- Q-Expression is strictly typed: convert with `ToString(...)` / `ToNumber(...)` when mixing text and numbers

**Conditional logic not working**
- Use the Q-Expression form `{% q If(condition, 'a', 'b') %}`, or Liquid `{% if %}` with plain variable names
- Text values need single quotes inside Q-Expressions: `$status = 'Active'`

**Empty values**
```
{% q If(IsBlank($optionalField), 'N/A', $optionalField) %}
```

**Number formatting**
```
Total: ${% q Round($total, 2) %}
Discount: {% q Round($discountPercent * 100, 1) %}%
```

## Quick Reference

| What You Want | Syntax | Example |
|---------------|--------|---------|
| Insert a value | `{{name}}` | `{{_row.firstName}}` |
| Calculation | `{% q expression %}` | `{% q $price * $quantity %}` |
| Conditional text | `{% q If(condition, 'a', 'b') %}` | `{% q If($total > 100, 'Free shipping', 'Standard rate') %}` |
| Current member name | `{% q $ActingMember.Name %}` | `{% q $ActingMember.Name %}` |
| Workbook field | `{% q $_f_<field> %}` | `{% q $_f_companyName %}` |
| Lookup from another sheet | `{% q $value:sheet@column:returnColumn %}` | `{% q $customerId:customers@id:name %}` |
| Liquid condition | `{% if ... %}...{% endif %}` | `{% if total > 100 %}VIP{% endif %}` |

### Common Functions in Q-Expressions
- `If(condition, trueValue, falseValue)` - Conditional logic
- `IsBlank(value)` - Check if a value is empty
- `Round(number, decimals)` - Round numbers
- `ToString(value)` - Convert to text for concatenation
- `CountList(list)` - Count items in a list

There is no built-in `TODAY()` or `NOW()`; define a q-function if you need the current date (see [Q-Expression](sheetyapp-q-expression.md#q-functions-custom-javascript-functions)).
