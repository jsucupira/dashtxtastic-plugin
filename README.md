# Dashtxtastic for Claude Code and GitHub Actions

Your AI agent writes the status doc. This repo turns it into a branded dashboard your client can open, behind a share link you control: lock it with a code, let it expire, or revoke it.

See a live example: [the Dashtxtastic roadmap](https://dashtxtastic.com/s/dashtxtastic-roadmap-th5t), published from a markdown file with this Action.

Two ways to publish:

- **Claude Code plugin.** Ask Claude to "publish our roadmap as a dashboard." It picks a render mode, writes the markdown to that mode's spec, uploads it, and hands back the share link.
- **GitHub Action.** Publish a markdown file on every push. The share URL stays the same across runs.

## Before you start

1. Create an account at [dashtxtastic.com](https://dashtxtastic.com).
2. Mint an API key at [Settings, Developer](https://dashtxtastic.com/settings/developer). Every plan includes the Developer API; the Free plan holds up to five dashboards.
3. Keep the key out of files and commits. Export it in your shell, or store it as a repository secret.

## Claude Code plugin

```
/plugin marketplace add jsucupira/dashtxtastic-plugin
/plugin install dashtxtastic@dashtxtastic
```

Then export your key before starting Claude Code:

```bash
export DTX_API_KEY="dtx_..."
```

Try:

- "Publish NEXT.md as a status dashboard and give me a share link."
- "Turn docs/roadmap.md into a stages roadmap, locked with an access code."
- "Update the dashboard with today's changes."

The plugin keeps a `.dashtxtastic.json` file at your repo root that maps source files to their dashboards, so updates reuse the same project and link. It holds ids and URLs only, so it is safe to commit.

## GitHub Action

Copy [`examples/publish-status-page.yml`](examples/publish-status-page.yml) into `.github/workflows/`, add a `DASHTXTASTIC_API_KEY` repository secret, and push.

```yaml
- uses: jsucupira/dashtxtastic-plugin/publish-action@v0.1.0
  with:
    api-key: ${{ secrets.DASHTXTASTIC_API_KEY }}
    file: STATUS.md
    render-mode: tile_dashboard
```

| Input | Default | Meaning |
|---|---|---|
| `api-key` | required | Developer API key, from a secret |
| `file` | required | Markdown file to publish |
| `project-name` | repository name | Reuses the project with exactly this name, or creates it |
| `render-mode` | `prose` | `prose`, `tile_dashboard`, `list_dashboard`, `infographic_before_after`, `infographic_stages`, `project_hub` |
| `target-path` | `main.md` | File name inside the project |
| `share` | `true` | Set to `false` to skip the public link |
| `share-slug` | auto | Slug prefix for a new link |
| `share-days` | `90` | Link lifetime, renewed on every run |

Outputs: `project-id` and `share-url`.

Each run renews the existing link rather than minting a new one, so the URL you sent last month keeps working.

## Render modes

| Content | Mode |
|---|---|
| Status report, plain sections | `prose` |
| Card per section | `tile_dashboard` |
| Bullets per section | `list_dashboard` |
| Current state vs future state | `infographic_before_after` |
| Phased roadmap with metrics | `infographic_stages` |
| Tracks with owners and status | `project_hub` |

Each mode expects a specific markdown structure. The plugin reads the live spec from the API before writing; for the Action, see the [docs](https://dashtxtastic.com/docs).

## License

MIT
