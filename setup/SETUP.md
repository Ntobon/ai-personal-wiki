# Setup

End-to-end setup for `personal-wiki`. Assumes you already have Supabase project `wjypineoplzwayvktorc` and both Claude Code profiles (`~/.claude-personal` and `~/.claude`) configured.

## 1. Local config

```bash
cp config.example.json config.json
# edit config.json — set user_email
```

## 2. Apply schema

Phase 2 deliverable — not yet written. Will live in `migrations/001_initial.sql`.

```bash
# applied via Supabase MCP (apply_migration) or psql against wjypineoplzwayvktorc
```

## 3. Install skills into both profiles

Source of truth is `skills/` in this repo. Copy into both:

```bash
for skill in wiki-ingest wiki-ask wiki-lint wiki-review; do
  cp -r "skills/$skill/" "$HOME/.claude-personal/skills/$skill/"
  cp -r "skills/$skill/" "$HOME/.claude/skills/$skill/"
done
```

After edits, push to Notion: `/skill-push`.

## 4. MCP configuration

### Personal profile (`~/.claude-personal/.mcp.json` or user-level config)

Already has Supabase MCP pointing at personal org — no changes needed. Optional: add `wiki-proxy` for parity with MOLT.

### MOLT profile (`~/.claude/.mcp.json`)

Cannot add a second Supabase MCP (single-org constraint). Add `wiki-proxy` as a stdio server:

```json
{
  "mcpServers": {
    "wiki-proxy": {
      "command": "node",
      "args": ["/absolute/path/to/personal-wiki/wiki-proxy/bin/server"],
      "env": {
        "WIKI_PROXY_CONFIG": "/home/nicolas/.claude-personal/wiki-proxy/config.json"
      }
    }
  }
}
```

`wiki-proxy` itself is built in Phase 2b.

### Mobile (claude.ai)

Uses personal Supabase MCP (already connected). No action.

## 5. wiki-proxy credentials (Phase 2b)

```bash
mkdir -p ~/.claude-personal/wiki-proxy
cat > ~/.claude-personal/wiki-proxy/config.json <<EOF
{
  "supabase_url": "https://wjypineoplzwayvktorc.supabase.co",
  "supabase_anon_key": "...",
  "user_email": "your-email@example.com"
}
EOF
chmod 600 ~/.claude-personal/wiki-proxy/config.json
```

## 6. Scheduled triggers (Phase 6)

Via `/schedule`. Cloud-only fuentes run server-side. Local-filesystem ingest (Claude Code logs, repos) runs via profile-scoped hooks or manual invocation.

## Smoke test

After Phases 1–3 done:

```bash
# From personal profile
ccp
> /wiki-ingest
# Expect: reads 50 queue items, creates ~15–25 articles

# From MOLT profile
ccd
> "ask the wiki: what do we know about <topic>?"
# Expect: wiki-proxy answers identically
```
