---
name: wiki-ingest
description: Pull from reading queue, digests, action items, Claude Code logs (both profiles), Notion, and repos; compile into wiki articles. Use this skill when the user says "/wiki-ingest", "compile wiki", "ingest into wiki", "actualizar wiki", or on scheduled runs. Phase 3 MVP covers reading queue only; other sources ship in later phases. Segments sources by platform — cloud sources run everywhere; local sources (Claude Code logs, repos) only run in the matching profile.
platform: both
version: 0.3.0
---

# wiki-ingest

Pull-based compile. Reads from `content.queue_items` (Phase 3 MVP), extracts entities worth a wiki article, creates or updates them via `wiki.upsert_article`, rebuilds backlinks, and logs ingest for idempotency.

**Phase 3 scope:** reading queue only. Digests, actions, Claude Code logs, Notion, repos come in later phases.

## Bootstrap

1. Read `config.json` from the project root if present (`personal-wiki/config.json`). Otherwise check memory for `wiki_project_id` + `user_email`, or ask.
2. `select wiki.get_user_context('<email>')` — cache `user_id`, `totals`, `recent_ingests`.
3. Project ID: `wjypineoplzwayvktorc` (same Supabase as content-queue).

## Transport

- **Personal profile / claude.ai mobile:** use `mcp__claude_ai_Supabase__*` tools directly.
- **MOLT profile:** use `mcp__wiki-proxy__*` (stdio MCP server — built in Phase 2b, not yet available). If the proxy MCP is missing, stop and tell the user MOLT ingest is blocked until Phase 2b ships.

Detect the transport at the start of the run. Remember which one for the whole session.

## Inputs not yet seen

```sql
select qi.*,
       array(select t.name from unnest(qi.tag_ids) tid
             join content.tags t on t.id = tid) as tags,
       c.name as category
  from content.queue_items qi
  left join content.categories c on c.id = qi.category_id
 where qi.user_id = $user_id
   and not exists (
     select 1 from wiki.sources s
      where s.user_id = qi.user_id
        and s.source_type = 'queue_item'
        and s.source_id = qi.id::text
   )
 order by qi.date_added desc;
```

If no rows, report "nothing new to ingest" and exit.

## Per-item compile loop

For each queue item, extract the **entities worth an article** — not the item itself. A queue item is raw material: one article about a tool, one about a person, one about a concept. Never ingest the queue item as a single "Article about this tweet" — that is noise.

### 1. Extract candidates

From `title`, `summary`, `key_takeaways`, `why_it_matters`, `source`, `tags`, `category`, infer a short list of candidate entities:

- **person** — named individuals: `@theo`, `Karpathy`, `Ashutosh Maheshwari`
- **project** — named products/codebases: `Hivemind`, `deep-project`, `MOLT`
- **concept** — techniques, patterns, decisions: `dynamic context injection`, `circuit breakers for agents`
- **tool** — software/services used: `Claude Code`, `pg_trgm`, `Supabase MCP`
- **decision** — explicit choices made or recorded

Skip purely ephemeral mentions (anyone quoted in passing, any tool merely namedropped). **A candidate must have 3+ substantive sentences of content extractable** from this item — otherwise do not create an article for it. If it hits an existing article, you may still add a short section.

### 2. Scope inference

- Queue-item category tagged "MOLT-related" or content mentioning MOLT engagements explicitly → `scope = 'molt'`
- Personal projects (Algoritmo unless MOLT-adjacent, finance-tracker, content-queue, this wiki) → `scope = 'personal'`
- Generic technical/industry content → `scope = 'shared'`

When ambiguous, prefer `shared`. Scope can always be corrected later via `/wiki-lint`.

### 3. Dedup

For each candidate, call `wiki.find_by_alias(user_id, name, type)`:
- `match = 'exact'` → update the existing article (step 4a)
- `match = 'fuzzy'` with top candidate similarity ≥ 0.55 and same type → treat as exact (probably the same entity with different casing/spelling); if < 0.55 or different type, treat as new
- `match = 'none'` → create new (step 4b)

### 4a. Update path

Read the existing article with `wiki.read_article(user_id, slug)`. Add a short new section with:
- A header naming the source (`## Notes from @theo on dynamic-context injection (2026-04-08)`)
- 3+ substantive sentences extracted from the queue item, in Wikipedia tone
- Wikilinks `[[other-slug]]` for any already-existing entities referenced

Call `wiki.upsert_article` with the merged `content_md`. The RPC will preserve `manually_edited=true` unless `force=true`, so respect that — if it returns `action='skipped'`, log it and continue.

### 4b. Create path

Build a fresh article:

```markdown
# <Title>

<Summary paragraph: 2–3 sentences naming what this is, grounded in the queue item.>

## Context
<2–4 sentences: where it came from, who is involved, why it was captured.>

## Notes from <source>
<3+ sentences paraphrased from key_takeaways/why_it_matters. Attribution, not assertion. Max 2 direct quotes across the whole article.>

## Related
- [[slug-a]] — one-line reason
- [[slug-b]] — one-line reason
```

Slug rules: lowercase, dashes, ASCII, disambiguate collisions by adding type or context (`alex-ramirez` vs `alex-cliente-molt`). For tools/products, use the canonical name; for people, `firstname-lastname`.

`aliases` must include every spelling/casing variant you saw in the queue item + any obvious shortenings.

Call `wiki.upsert_article` with the full payload:

```json
{
  "user_id": "...",
  "slug": "...",
  "title": "...",
  "type": "concept|person|project|tool|decision",
  "scope": "personal|molt|shared",
  "content_md": "...",
  "summary": "...",
  "tags": ["..."],
  "aliases": ["..."],
  "sources": [{"type": "queue_item", "id": "<queue_item_id>", "ingested_at": "..."}]
}
```

### 5. Rebuild links

For every article you touched in this item (created or updated), call `wiki.rebuild_links(article_id)`. Note any slugs in the `missing` return — those are dangling wikilinks; you may create a stub for them in a follow-up pass, or leave them for lint.

### 6. Log source

Once all candidates from this queue item are processed:

```
wiki.log_source({
  user_id, source_type: 'queue_item', source_id: <queue_item_id>,
  source_scope: <dominant scope used>,
  articles_touched: [<every article.id you touched>]
})
```

The unique constraint `(user_id, source_type, source_id)` makes replay a no-op — run `/wiki-ingest` twice and nothing duplicates.

## Error behavior

- `upsert_article` returns `action='skipped'` → log in your run summary; do not retry.
- `rebuild_links` missing slugs → collect and report; do not fail the run.
- Any RPC error → abort this queue item, continue with the next. Never half-log.

## Run summary

At the end, print:
```
Ingest complete.
  Items read:     <N>
  Articles made:  <M> created, <U> updated, <S> skipped
  Links added:    <L>
  Dangling slugs: <list if any>
```

## Calibration

Start conservative. If the first run creates 25+ articles from 10 queue items, you are over-extracting — tighten the 3+ sentence rule or reject the candidate. Target is **1.5–2 articles per queue item** on average at MVP.

## What this skill does NOT do (yet)

- Digests, action items, Claude Code logs, Notion, repos → Phases 7–9
- Contradiction detection → Phase 5 (`wiki-lint`)
- Write-backs from queries → Phase 4 (`wiki-ask`)
- Scheduled runs → Phase 6
