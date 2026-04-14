# Phase 3 — wiki-ingest MVP

Gate: 50 queue items → ~15–25 articles from personal profile; identical from MOLT via proxy.

## Scope

Reading queue only. Other sources (digests, actions, logs, Notion, repos) come in later phases.

## Deliverables

- `skills/wiki-ingest/SKILL.md` complete implementation for queue items
- Transport abstraction: detect profile, pick MCP (official vs proxy)
- Inline lint: trigram dedup, `rebuild_links`, contradiction flag
- Idempotency via `wiki.log_source`

## Exit criteria

```
# Personal profile
> /wiki-ingest
# → 15–25 articles created, logs in wiki.sources

# MOLT profile
> /wiki-ingest
# → 0 new articles (already ingested), same log state
```

TBD.
