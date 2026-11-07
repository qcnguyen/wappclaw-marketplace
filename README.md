# Wappclaw Marketplace

The first-party catalogue for Wappclaw, and **every server's built-in default marketplace**: it
appears in the admin app (top bar → **Marketplace**, or Plugins → **Browse marketplace**) with no
setup, and installs in one click. (A server can point the default elsewhere with
`WAPP_DEFAULT_MARKETPLACE=<git url>`, or turn it off with `WAPP_DEFAULT_MARKETPLACE=off`.)

This repository **holds the source code of everything it offers**: each item is a folder here,
listed in [`marketplace.json`](marketplace.json). One commit of this repository is therefore
exactly what every server installs, and reviewing a pull request here is reviewing the code
that will run.

| Folder | What is in it |
| --- | --- |
| [`plugins/`](plugins) | One folder per plugin — `plugin.json`, `GUIDELINE.md` and its scripts. |
| [`schema/`](schema) | JSON Schema for `marketplace.json`. |
| [`docs/WRITING-A-PLUGIN.md`](docs/WRITING-A-PLUGIN.md) | How to write a plugin. |
| [`WRITING-A-MARKETPLACE.md`](WRITING-A-MARKETPLACE.md) | How to publish **your own** marketplace. |

Today a server installs **plugins**. Mini-apps, interactive forms, form components, skills,
sub-agents, MCP servers, commands and pipelines will follow, as more folders (`mini-apps/`,
`forms/`, …) and more `type`s in the index — the format already has room for them.

## Not the only marketplace

A server can follow **any number of marketplaces**: this one, your team's private one, a
vendor's. Each is just a git repository. See [WRITING-A-MARKETPLACE.md](WRITING-A-MARKETPLACE.md)
to build one — the format is the same one used here.

## Adding an item here

1. Add its folder under `plugins/<id>/` (see [docs/WRITING-A-PLUGIN.md](docs/WRITING-A-PLUGIN.md)).
2. Add an entry to `items` in `marketplace.json`:
   ```json
   { "type": "plugin", "id": "my-tool", "source": "plugins/my-tool",
     "name": "My Tool", "summary": "One line for the card.", "categories": ["productivity"] }
   ```
3. Validate: `npx ajv-cli validate --spec=draft2020 -s schema/marketplace.schema.json -d marketplace.json`.
4. Open a pull request. Servers see the change on their next **Fetch latest**.

Installed items run on the server as the server's user, with no sandbox — so nothing is merged
here that we would not install ourselves.
