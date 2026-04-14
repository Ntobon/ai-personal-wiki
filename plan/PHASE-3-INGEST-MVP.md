# Phase 3 — wiki-ingest MVP

## Status

Personal-profile path done (2026-04-14). MOLT-profile path blocked on Phase 2b (wiki-proxy MCP server); skill detects missing proxy and bails gracefully.

## Deliverables

- [x] `skills/wiki-ingest/SKILL.md` complete implementation for queue items (version 0.3.0)
- [x] Skill installed at `~/.claude-personal/skills/wiki-ingest/`
- [x] Inline dedup via `wiki.find_by_alias` before create
- [x] `wiki.rebuild_links` after each upsert
- [x] Idempotency via `wiki.log_source`
- [ ] Transport abstraction for MOLT profile — blocked on Phase 2b

## Smoke-test result (5 queue items)

- 6 articles created (5 topical + `molt` cross-cutting)
- 17 links rebuilt, 0 orphans
- 5 rows in `wiki.sources`; replay is a no-op
- Search, scope filter, backlinks all return correct counts

## Exit criteria

- [x] Personal profile: real articles in prod from real queue items
- [ ] MOLT profile: Phase 2b required
- [ ] Full 50-item run (user invokes `/wiki-ingest` when ready)
