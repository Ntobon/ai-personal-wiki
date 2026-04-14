# wiki-proxy

Stdio MCP server that exposes the personal wiki (`wjypineoplzwayvktorc`) as 13 `wiki_*` tools.

## Why

Supabase MCP is single-org. The MOLT Claude Code profile's MCP is already scoped to the MOLT organisation and cannot add a second Supabase MCP for the personal organisation. `wiki-proxy` runs as a separate stdio MCP server and talks to the personal Supabase over HTTPS, so tool calls from MOLT profile never touch that profile's MCP.

## Install

```bash
npm install
npm run build
```

## Configure

Two options:

### a) Config file (recommended for persistent use)

```bash
mkdir -p ~/.claude-personal/wiki-proxy
cat > ~/.claude-personal/wiki-proxy/config.json <<EOF
{
  "supabase_url": "https://wjypineoplzwayvktorc.supabase.co",
  "supabase_key": "<publishable key, starts with sb_publishable_>",
  "user_email": "you@example.com"
}
EOF
chmod 600 ~/.claude-personal/wiki-proxy/config.json
```

Then set `WIKI_PROXY_CONFIG=/home/you/.claude-personal/wiki-proxy/config.json` in the MCP entry.

### b) Environment variables

```
WIKI_PROXY_SUPABASE_URL=...
WIKI_PROXY_SUPABASE_KEY=...
WIKI_PROXY_USER_EMAIL=you@example.com
```

## Register with the MOLT Claude Code profile

Add to `~/.claude/.mcp.json` (or user-level Claude Code config):

```json
{
  "mcpServers": {
    "wiki-proxy": {
      "command": "node",
      "args": ["/absolute/path/to/personal-wiki/wiki-proxy/dist/index.js"],
      "env": {
        "WIKI_PROXY_CONFIG": "/home/you/.claude-personal/wiki-proxy/config.json"
      }
    }
  }
}
```

The existing MOLT Supabase MCP stays untouched. Tools appear under `mcp__wiki-proxy__*`.

## Tools

Each tool maps 1:1 to a `public.wiki_*` wrapper, which in turn delegates to the real `wiki.*` function. PostgREST exposes only `public` by default — the wrappers run `SECURITY DEFINER` with a locked `search_path` so the caller never needs `USAGE` on the `wiki` schema.

| Tool | RPC |
|---|---|
| `wiki_get_user_context` | `wiki.get_user_context(email)` |
| `wiki_list_index` | `wiki.list_index(user_id, scope?)` |
| `wiki_read_article` | `wiki.read_article(user_id, slug)` |
| `wiki_search` | `wiki.search(user_id, query, scope?, limit?)` |
| `wiki_find_by_alias` | `wiki.find_by_alias(user_id, name, type?)` |
| `wiki_upsert_article` | `wiki.upsert_article(payload)` |
| `wiki_rebuild_links` | `wiki.rebuild_links(article_id)` |
| `wiki_log_source` | `wiki.log_source(payload)` |
| `wiki_recent_ingests` | `wiki.recent_ingests(user_id, limit?)` |
| `wiki_orphans` | `wiki.orphans(user_id)` |
| `wiki_record_correction` | `wiki.record_correction(payload)` |
| `wiki_reject_writeback` | `wiki.reject_writeback(payload)` |
| `wiki_lint_summary` | `wiki.lint_summary(user_id)` |

## Smoke test

```bash
WIKI_PROXY_SUPABASE_URL=... WIKI_PROXY_SUPABASE_KEY=... WIKI_PROXY_USER_EMAIL=... npm run smoke
```

Speaks the MCP stdio protocol directly, verifies `initialize`, `tools/list`, and a handful of `tools/call` round-trips.

## Node version

Requires Node ≥ 18 to run; `@supabase/supabase-js` warns on < 20 and will drop support for 18 in a future release. Pin to Node 20 LTS when setting up the MCP entry on a new machine.
