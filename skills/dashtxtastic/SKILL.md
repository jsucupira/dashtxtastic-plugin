---
name: dashtxtastic
description: "Publish markdown as a branded, shareable one-page dashboard via the Dashtxtastic API (https://dashtxtastic.com). Two paths: (1) pick a render mode (prose, tile or list dashboard, before/after infographic, stages roadmap, or project hub), author markdown to that mode's spec, upload it, and return the share link; (2) host a finished .html page as an html project behind the same kind of share link. Use when the user asks for a status page, project overview, roadmap, before/after comparison, status hub, or any shareable page built from markdown, or wants to share an existing HTML page with people who have no account."
---

# Dashtxtastic

Publish a one-page dashboard by driving the Dashtxtastic Developer API. You author markdown that follows the chosen render mode's `authoringPrompt`; the hosted renderer turns it into a self-contained HTML page behind a share link the user controls (access code, expiry, revoke).

## When to activate

- "Make a dashboard / one-pager / status page for X"
- "Publish our roadmap / NEXT.md / status doc so the client can see it"
- "Before and after comparison of X"
- "Project hub / status hub across these tracks"
- "Share this HTML page with someone outside the team"

For long narrative docs (many headings of prose), suggest the `prose` mode or a plain markdown viewer instead of a visual mode.

## Prerequisites

```bash
# Required: bearer token minted at https://dashtxtastic.com/settings/developer
export DTX_API_KEY="dtx_..."
# Optional: defaults to https://dashtxtastic.com
export DTX_BASE_URL="https://dashtxtastic.com"
```

If `DTX_API_KEY` is not set, stop and ask the user to export it in their shell profile. Never hard-code the key in a command, a file, a commit, or a message.

Every plan can use the API. A `402 project_cap_reached` response means a Free account already holds five projects; quote the response `message` to the user.

## Project registry

Keep a `.dashtxtastic.json` file at the repository root so "update the dashboard" reuses the same project and share link across sessions instead of creating duplicates. It holds ids and names only, never keys, so it is safe to commit.

```json
{
  "projects": {
    "<source path relative to repo root>": {
      "id": "<project guid>",
      "name": "<dashboard name>",
      "renderMode": "<mode id, or null for html projects>",
      "projectType": "markdown | html",
      "sourceFile": "<uploaded file name, e.g. main.md>",
      "shareUrl": "<https://dashtxtastic.com/s/...>"
    }
  }
}
```

Rules:

1. Before creating a project, look up the source path. If it is there, reuse its `id` and `PUT` the file again.
2. On a registry miss when the user clearly means an existing dashboard, search first with `GET /api/v1/projects?q=<name>` and adopt an exact name match. Never silently create a second project for the same source.
3. Set each new project's `description` to `source: <relative path>` so the registry can be rebuilt from the API if the file is lost.
4. Update the entry after every successful create, upload, or share-link call.

## Workflow

### 1. Read the live render-mode catalog

```bash
curl -sS -H "Authorization: Bearer $DTX_API_KEY" \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/render-modes"
```

Read `data.modes[].authoringPrompt` for the mode you intend to use, top to bottom, before writing markdown. The live prompt overrides anything in this file.

### 2. Pick a render mode and confirm it

| Content shape | Mode `id` |
|---|---|
| Plain sections of prose, status report | `prose` |
| Card grid, one tile per section | `tile_dashboard` |
| Section-by-section bullet lists | `list_dashboard` |
| Current state vs future state, migration | `infographic_before_after` |
| Multi-phase roadmap with work items and metrics | `infographic_stages` |
| Hub of tracks or workstreams with owners and status | `project_hub` |

There is no process-flow diagram mode. For a flow or parallel-paths request, re-shape the content into `project_hub` tracks and confirm that with the user.

Propose the mode in one line with the reason, and wait for the user to confirm.

### 3. Create the project (only on a registry miss)

```bash
curl -sS -X POST -H "Authorization: Bearer $DTX_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"<short name>","renderMode":"<mode id>","description":"source: <relative path>"}' \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/projects"
```

Capture `data.id` from the `201` response and write the registry entry.

### 4. Author the markdown

Write the file to match the chosen mode's `authoringPrompt` exactly. The renderer is strict: a missing section or wrong heading level produces broken output rather than a friendly error.

- Use only facts from the user's sources. Never invent metrics, owners, or dates.
- Convert relative dates ("end of Q3") to absolute dates when the source allows it.
- Link to another file in the same project with a relative path, `[Label](sibling.md)`. Use `/view/<other-project-id>` only for links to a different project.
- Markdown projects accept `.md` files only. Images cannot be uploaded; use absolute `https://` image URLs, which are embedded at render time.

### 5. Upload (renders and publishes in one call)

```bash
curl -sS -X PUT -H "Authorization: Bearer $DTX_API_KEY" -H "Content-Type: text/markdown" \
  --data-binary @<file>.md \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/projects/<id>/files/main.md"
```

Path rules: lowercase ASCII, ends in `.md`, no `..`, no leading slash, under 1 MiB. Add `?renderMode=<mode>` to give a sibling file a different mode from the project default. Add an `Idempotency-Key: <uuid>` header when retrying after a timeout.

### 6. Share

Owner routes (`/view/<id>`) need the user's login. For anyone else, mint or reuse the public link:

```bash
# Keep an existing URL alive (also revives an expired link). 404 means there is no link yet.
curl -sS -X POST -H "Authorization: Bearer $DTX_API_KEY" -H "Content-Type: application/json" \
  -d '{"expiresInDays":90}' \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/projects/<id>/share-links/extend"

# Create one when extend returned 404.
curl -sS -X POST -H "Authorization: Bearer $DTX_API_KEY" -H "Content-Type: application/json" \
  -d '{"slugBase":"q3-roadmap","expiresInDays":90}' \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/projects/<id>/share-links"
```

Optional body fields on create: `filePath` scopes the link to one file, `accessCode` gates it behind a passcode (`""` clears it). Share `data.url`. Prefer extend over re-creating: create on a lapsed link mints a new random suffix and breaks the URL people already have.

For anything non-public, set an access code and send the code separately from the link.

### 7. Report back

Tell the user the mode and why, the share URL, and two or three concrete tweaks they could ask for next.

## Hosting a finished HTML page

Use this when the deliverable already exists as an `.html` file. Nothing is rendered; the file is served as uploaded, plus a `<base>` tag so sibling links resolve.

```bash
curl -sS -X POST -H "Authorization: Bearer $DTX_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"<short name>","projectType":"html","description":"source: <relative path>"}' \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/projects"

curl -sS -X PUT -H "Authorization: Bearer $DTX_API_KEY" -H "Content-Type: text/html" \
  --data-binary @page.html \
  "${DTX_BASE_URL:-https://dashtxtastic.com}/api/v1/projects/<id>/files/page.html"
```

Then share exactly as in step 6. Do not edit someone else's HTML before uploading. Html projects take `.html` files only and reject `?renderMode=` with `409`.

## Errors

| HTTP | Meaning | What to do |
|---|---|---|
| 401 | Key missing, malformed, or revoked | Ask the user to mint a new key at `/settings/developer` |
| 402 `project_cap_reached` | Free plan already holds five projects | Quote the message; archive or delete a project, or upgrade at `/pricing` |
| 409 `project_type_unsupported` | Render-mode or editor operation on an html project | Drop `?renderMode=`; upload `.html` only |
| 412 | Tried to delete the main or last file | Promote another file with `POST /files/set-main` first |
| 413 | File over 1 MiB | Split the content across files |
| 422 | Markdown does not match the mode's structure | Re-read the `authoringPrompt` and fix the structure |
| 429 | Rate limit | Wait a minute; do not retry in a tight loop |

Errors use `{ "status": "error", "error": "<code>", "message": "..." }`. Quote `message` when reporting a failure.

## Reference

- API base: `https://dashtxtastic.com/api/v1`
- OpenAPI: `https://dashtxtastic.com/api/openapi/v1.json`
- API docs: `https://dashtxtastic.com/api/docs/index.html`
- Mint keys: `https://dashtxtastic.com/settings/developer`
