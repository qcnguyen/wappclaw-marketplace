# Jira Cloud, through its REST API

This plugin runs **curl** already authenticated to a Jira site. Two things are set
up for you and nothing else is:

- **`curl -n`** picks up the credential on its own (it is in a `.netrc` this plugin
  owns). Never put a token, a header or a `-u` flag in a command — there is nothing
  to supply.
- **`$JIRA_BASE`** is the API root for this site
  (`https://api.atlassian.com/ex/jira/<cloudId>`). It cannot be guessed, so build
  every URL from it.

```bash
curl -sn "$JIRA_BASE/rest/api/3/myself" | jq -r .displayName
```

`$JIRA_SITE_URL` is the site's own address, for links you show a person:
`$JIRA_SITE_URL/browse/KEY-123`.

**Whose account this is.** One Atlassian account. Its permissions are the plugin's
permissions, and Jira *hides* what an account cannot see rather than forbidding it —
so a project it lacks access to reports as "does not exist".

## Ask for what you need, and nothing else

A Jira issue is a very large JSON document — a hundred-odd fields, most of them
empty custom fields. Always narrow it, twice over:

```bash
# `fields` narrows what Jira sends; jq narrows what you read
curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123?fields=summary,status,assignee,description" \
  | jq '{key, summary: .fields.summary, status: .fields.status.name, assignee: .fields.assignee.displayName}'
```

`fields=*all` exists and is almost never what you want.

## Reading

| Task | Call |
|---|---|
| Who am I | `curl -sn "$JIRA_BASE/rest/api/3/myself"` |
| One issue | `curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123?fields=summary,status,description"` |
| Its comments | `curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123/comment"` |
| Allowed transitions | `curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123/transitions"` |
| Search | see below — the endpoint has changed |
| Projects | `curl -sn "$JIRA_BASE/rest/api/3/project/search?maxResults=50"` |
| One project | `curl -sn "$JIRA_BASE/rest/api/3/project/KEY"` |
| Field ids (for custom fields) | `curl -sn "$JIRA_BASE/rest/api/3/field"` |
| What a project needs to create | `curl -sn "$JIRA_BASE/rest/api/3/issue/createmeta?projectKeys=KEY"` |
| Find a user's accountId | `curl -sn "$JIRA_BASE/rest/api/3/user/search?query=someone@example.com"` |

## Searching — `/search/jql`, not `/search`

**`GET /rest/api/3/search` has been removed and answers HTTP 410.** Use
`/rest/api/3/search/jql`:

```bash
curl -sn --get "$JIRA_BASE/rest/api/3/search/jql" \
  --data-urlencode 'jql=project = DD AND status != Done ORDER BY created DESC' \
  --data-urlencode 'fields=key,summary,status,assignee' \
  --data-urlencode 'maxResults=20' \
  | jq -r '.issues[] | "\(.key)  [\(.fields.status.name)]  \(.fields.summary)"'
```

`--get --data-urlencode` is the reliable way to send JQL: it URL-encodes the spaces,
`=` and quotes for you, and hand-encoding a query is a guaranteed source of 400s.

Three things about this endpoint specifically:

- **JQL must be bounded.** An open query is refused with *"Unbounded JQL queries are
  not allowed here. Please add a search restriction to your query."* — so
  `ORDER BY created DESC` on its own fails. Restrict it: `project = X`,
  `assignee = currentUser()`, `updated >= -7d`.
- **Paging is `nextPageToken`, not `startAt`.** The response carries
  `nextPageToken` and `isLast`; there is no `total`. Pass the token back as
  `nextPageToken=…` for the next page, and stop when `isLast` is true. Do not
  expect a result count — if you need one, use JQL you can bound and count what
  you receive.
- **Nothing tells you a page was the last one except `isLast`.** A page of exactly
  `maxResults` issues is not evidence either way.

## Writing

Reads are safe; **writes change somebody's tracker.** Do exactly what was asked,
and echo back the key of anything you create or change.

```bash
# Comment (v2 takes plain text — see the ADF note below)
curl -sn -X POST "$JIRA_BASE/rest/api/2/issue/KEY-123/comment" \
  -H 'Content-Type: application/json' \
  --data '{"body":"Deployed to staging."}'

# Edit fields
curl -sn -X PUT "$JIRA_BASE/rest/api/2/issue/KEY-123" \
  -H 'Content-Type: application/json' \
  --data '{"fields":{"summary":"New summary"}}'

# Transition — the id comes from the transitions endpoint, names are not accepted
curl -sn -X POST "$JIRA_BASE/rest/api/3/issue/KEY-123/transitions" \
  -H 'Content-Type: application/json' \
  --data '{"transition":{"id":"31"}}'

# Create
curl -sn -X POST "$JIRA_BASE/rest/api/2/issue" \
  -H 'Content-Type: application/json' \
  --data '{"fields":{"project":{"key":"DD"},"issuetype":{"name":"Task"},"summary":"...","description":"..."}}'
```

Build a JSON body with `jq -n` rather than by hand when any value comes from user
text — a stray quote or newline otherwise produces an invalid body:

```bash
body=$(jq -n --arg t "$TEXT" '{body: $t}')
curl -sn -X POST "$JIRA_BASE/rest/api/2/issue/KEY-123/comment" \
  -H 'Content-Type: application/json' --data "$body"
```

**A successful write returns `201` (create) or `204` (update/transition) with an
empty body.** Add `-w '\n%{http_code}\n'` if you want to see it, and do not treat
an empty response as a failure.

## v3 or v2 — and this is the one that saves the most trouble

Both are available on this site. They differ in how rich-text fields
(`description`, comment `body`) are represented:

- **v3 uses ADF**, Atlassian Document Format: a nested JSON document
  (`{"type":"doc","version":1,"content":[…]}`). Reading it means walking the tree;
  writing it means constructing one.
- **v2 uses plain strings** for the same fields. Verified on this site: the same
  issue's description comes back as an ADF object from `/rest/api/3/` and as a
  plain string from `/rest/api/2/`.

So: **use v2 for anything involving description or comment text**, in both
directions, unless specific formatting was asked for. Use v3 for everything else
(it is the current API and `/search/jql` lives there). Mixing them per call is
normal and fine.

## What is not available here

**The Agile API (`/rest/agile/1.0/…`) is out of scope for this credential** —
boards, sprints and backlogs answer `401 {"code":401,"message":"Unauthorized; scope
does not match"}`, and no amount of retrying changes that. Say so rather than
working around it. What you *can* still do: an issue's sprint is a custom field on
the issue itself, so `fields=customfield_XXXXX` (find the id via
`/rest/api/3/field`) reads sprint membership, and JQL understands `sprint in
openSprints()`.

## What a failure means

- **`401`** — the credential. The token has expired, been revoked, or does not match
  the email. A human re-authenticates the plugin from the admin app; you cannot.
  Report it and stop. (A `401` mentioning *"scope does not match"* is different: that
  is an endpoint this token cannot reach, above.)
- **`403`** — authenticated but not permitted. A real permission, not a retry.
- **`404` on an issue key you believe in** — usually the account cannot see that
  project. Check with `/rest/api/3/project/search`; if it is not listed, it is
  permissions, not a typo.
- **`400` on a search** — unbounded JQL, or a JQL syntax error. The response body
  says which; read it.
- **`410`** — you called `/rest/api/3/search`. Use `/search/jql`.
- **`429`** — rate limited. Back off and retry once, more slowly; do not hammer.

`curl` exits **0** for all of these: the request succeeded, the answer was no. Read
the body, or ask for the status with `-w '\n%{http_code}\n'`; do not judge a call by
curl's exit code alone.
