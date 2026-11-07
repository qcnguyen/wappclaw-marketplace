# Writing a marketplace

A **marketplace** is a git repository that a Wappclaw server browses and installs from. Anyone
can publish one — a team keeping its internal plugins private, a vendor shipping plugins for its
product, a community collection. An administrator adds it in the admin app (Marketplace →
**Marketplaces** → **Add marketplace**), and a server can follow as many as it likes.

This repository is a working example; copy its shape.

## 1. Layout

The marketplace **contains the source code** of every item it offers. Each item is one folder:

```
my-marketplace/
├── marketplace.json          ← the index (required for anything beyond a plain plugin repo)
├── plugins/
│   ├── acme-crm/             ← one plugin: plugin.json, GUIDELINE.md, install.sh, run.sh, …
│   │   └── icon.svg          ← optional; shown on the card
│   └── acme-billing/
├── mini-apps/                ← later: one folder per mini-app (app.json, index.html, api/, …)
└── README.md
```

Folder names are yours; the index says where each item is. `plugins/<id>/` is the convention.

An item's `source` must be a folder **in this repository**. A marketplace cannot point at
another repository: what you publish at a commit is what gets installed, nothing more.

## 2. `marketplace.json`

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/qcnguyen/wappclaw-marketplace/main/schema/marketplace.schema.json",
  "formatVersion": 1,
  "name": "Acme for Wappclaw",
  "description": "Plugins for Acme CRM and Acme Billing.",
  "publisher": { "name": "Acme Ltd", "url": "https://acme.example", "email": "dev@acme.example" },
  "homepage": "https://github.com/acme/wappclaw-marketplace",
  "categories": [ { "id": "crm", "label": "CRM" } ],
  "items": [
    {
      "type": "plugin",
      "id": "acme-crm",
      "source": "plugins/acme-crm",
      "name": "Acme CRM",
      "summary": "Search accounts, log calls and update deals.",
      "categories": ["crm"],
      "tags": ["accounts", "deals"],
      "icon": "plugins/acme-crm/icon.svg",
      "license": "MIT",
      "homepage": "https://acme.example/docs/wappclaw",
      "requires": { "wappclaw": ">=0.1.30" }
    }
  ]
}
```

### Top level

| Key | Required | Meaning |
| --- | --- | --- |
| `formatVersion` | yes | `1`. A server refuses a higher number it does not understand, with a message. |
| `items` | yes | The items, below. |
| `name`, `description` | | Shown on the marketplace's card. `name` defaults to the repository's name. |
| `publisher` | | `{ name, url?, email? }` — who maintains it. |
| `homepage` | | Where to read more. |
| `categories` | | `[{ id, label, description? }]` — the vocabulary items' `categories` use. |

### An item

| Key | Required | Meaning |
| --- | --- | --- |
| `type` | yes | What it is. `plugin` today. Reserved: `mini-app`, `interactive-form`, `form-component`, `skill`, `sub-agent`, `mcp-server`, `command`, `pipeline`. |
| `source` | yes | Its folder in this repository: `"plugins/acme-crm"` or `{ "path": "plugins/acme-crm" }`. |
| `id` | | The id it installs under. Defaults to what its own manifest says (a plugin's `plugin.json` `name`, slugified). Give it explicitly — it is the item's identity. |
| `name`, `summary`, `description` | | Card text. Default: from the item's own manifest. |
| `version` | | Only used when the item's manifest has none — `plugin.json`'s `version` wins. |
| `categories`, `tags` | | Search and filtering. |
| `icon` | | An image in this repository (`.svg`, `.png`, `.webp`, `.jpg`, ≤ 512 KB) or an `https://` URL. An `icon.svg`/`icon.png` in the item's folder is picked up without this. |
| `publisher`, `homepage`, `license` | | Shown on the card. |
| `requires` | | `{ wappclaw?: ">=x.y.z", items?: [{ type, id }] }`. Shown; not enforced yet. |
| `deprecated` | | A sentence saying what to use instead. Still listed, flagged. |

## 3. Rules a server applies

- **The item's own manifest is the truth.** The version shown, the version compared and the files
  installed all come from the item's folder (`plugin.json` for a plugin). The index curates how it
  is presented.
- **`type` + `id` must be unique** within your marketplace.
- **Unknown keys are ignored**, so a server running an older version still reads a marketplace
  written for a newer one. An item of a type the server cannot install yet is shown as *coming soon*.
- **A broken entry does not break the marketplace.** It is skipped, and the reason is shown on the
  marketplace's card in the admin app. Fix it and push.
- **Item ids are global on a server.** If two marketplaces both offer a plugin `jira`, a server can
  have only one of them installed; the admin app says which marketplace the installed copy came from
  and asks before replacing it. Choose ids that will not collide — prefix them with your name
  (`acme-crm`, not `crm`).

## 4. No index at all

A repository without `marketplace.json` still works: every folder (up to three levels deep) holding
a known manifest file — `plugin.json` today — is offered as an item, named by its manifest. That is
enough for a handful of plugins; add an index when you want names, categories and icons.

## 5. Private marketplaces

Host the repository anywhere git can clone over https or ssh. For a private one, the administrator
saves a credential on the **Credentials** page and picks it when adding the marketplace. Nothing
about the format changes.

## 6. Publishing a change

Push to the branch the servers follow (its default branch unless they chose another). Servers pick it
up when an administrator presses **Fetch latest**; an installed item whose files changed shows
**Update available**, and updating keeps the item's settings, secrets and state.

## 7. Checklist

- [ ] `marketplace.json` validates against [`schema/marketplace.schema.json`](schema/marketplace.schema.json).
- [ ] Every `source` folder exists and holds the item's manifest.
- [ ] Ids are prefixed so they will not collide with other marketplaces.
- [ ] Every plugin follows [docs/WRITING-A-PLUGIN.md](docs/WRITING-A-PLUGIN.md) — in particular, its
      `install.sh` provisions what it needs unattended.
- [ ] Added the repository to a test server and installed each item once.

What a marketplace offers runs on the server as the server's user, with no sandbox. Publish only
what you would install yourself, and expect administrators to read it before they do.
