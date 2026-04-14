# Phase 2b — wiki-proxy MCP server

Gate: from MOLT profile, `mcp__wiki-proxy__list_index` returns `[]` without error.

## Why

Supabase MCP is single-org. MOLT profile's Supabase MCP already points at MOLT org and cannot host a second Supabase MCP for the personal org. The proxy exposes `wiki_*` tools as a distinct MCP server, so both profiles can reach the personal wiki.

## Deliverables

- `wiki-proxy/` — TypeScript project using `@modelcontextprotocol/sdk`
  - `src/index.ts` — stdio MCP server entry
  - `src/tools.ts` — tool definitions mapping 1:1 to wiki RPCs
  - `src/supabase.ts` — PostgREST or `supabase-js` client
  - `bin/server` — executable entry
  - `package.json`, `tsconfig.json`
- Credentials config schema: `~/.claude-personal/wiki-proxy/config.json` (0600)
- MOLT profile `.mcp.json` snippet (documented in `setup/SETUP.md`)

## Open questions

- TypeScript vs Bun vs Python — default TS for SDK parity
- `anon_key` + `SECURITY DEFINER` RPCs vs `service_role_key` — default anon
- Schema version check at startup — warn on drift

## Exit criteria

From MOLT (`ccd`):
```
> call mcp__wiki-proxy__list_index
[]
```

From Personal (`ccp`), same call via Supabase MCP: identical result.
