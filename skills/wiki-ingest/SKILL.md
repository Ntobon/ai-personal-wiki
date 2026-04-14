---
name: wiki-ingest
description: Pull from reading queue, digests, action items, Claude Code logs (both profiles), Notion, and repos; compile into wiki articles. Use this skill when the user says "/wiki-ingest", "compile wiki", "ingest into wiki", "actualizar wiki", or on scheduled runs. Cloud sources run from any profile or mobile; local-filesystem sources (Claude Code logs, repos) only run in the matching Claude Code profile. Segments inputs, dedups, enforces 3+ substantive sentences per article, idempotent on replay.
platform: both
version: 0.4.0
---

# wiki-ingest

Pull-based compile. Extracts wiki-worthy entities from new material and writes them through `wiki.upsert_article` → `wiki.rebuild_links` → `wiki.log_source`.

## Bootstrap

1. Read `personal-wiki/config.json` if present; else memory; else ask.
2. `select wiki.get_user_context('<email>')` — cache `user_id` and `recent_ingests`.
3. Supabase project: `wjypineoplzwayvktorc`.

## Transport

- **Personal profile / mobile** → `mcp__claude_ai_Supabase__*`.
- **MOLT profile** → `mcp__wiki-proxy__*` (Phase 2b). Bail with a clear message if unavailable.

## Sources

Sources are segmented by where they live. A single run can combine multiple.

### Cloud sources (any platform)

| Source | Table | `source_type` | `source_id` |
|---|---|---|---|
| Reading queue | `content.queue_items` | `queue_item` | `id::text` |
| Digests | `content.digests` | `digest` | `id::text` |
| Action items | `content.action_items` | `action_item` | `id::text` |
| Notion pages | Notion MCP | `notion_skill` | Notion page ID |

### Local sources (profile-matched filesystem)

| Source | Path | `source_type` |
|---|---|---|
| Claude Code logs (personal) | `~/.claude-personal/projects/*.jsonl` | `claude_log_personal` |
| Claude Code logs (MOLT) | `~/.claude/projects/*.jsonl` | `claude_log_molt` |
| Repos | `~/personal/*`, `~/molt/*` (READMEs, CLAUDE.md, memory files) | `repo` |

A personal-profile run can read `claude_log_personal` and `~/personal/*` but NOT `claude_log_molt` or `~/molt/*` — the filesystem path is unreachable. MOLT profile sees the inverse. Mobile has no filesystem access.

## CLI flags (user may pass as arguments)

- `--sources=<csv>` → subset of sources. Default: all cloud-accessible + all matching-profile local.
- `--since=<iso>` → override "new since last log_source" with an explicit cutoff.
- `--dry-run` → classify and propose, but do not `upsert_article` or `log_source`.
- `--limit=<n>` → max items to process this run.

## Per-source extraction

### Reading queue (`content.queue_items`)

```sql
select qi.*,
       array(select t.name from unnest(qi.tag_ids) tid
             join content.tags t on t.id = tid) as tags,
       c.name as category
  from content.queue_items qi
  left join content.categories c on c.id = qi.category_id
 where qi.user_id = $user_id
   and not exists (select 1 from wiki.sources s
                    where s.user_id = qi.user_id
                      and s.source_type = 'queue_item'
                      and s.source_id = qi.id::text)
 order by qi.date_added desc;
```

A queue item is raw material. Extract worth-an-article **entities** — person, project, concept, decision, tool — from its `title`, `summary`, `key_takeaways`, `why_it_matters`. Target **1.5–2 articles per queue item**. See "Per-candidate flow" below.

### Digests (`content.digests`)

```sql
select d.*, array(select qi.title from content.digest_items di
                   join content.queue_items qi on qi.id = di.queue_item_id
                   where di.digest_id = d.id) as item_titles
  from content.digests d
 where d.user_id = $user_id
   and not exists (select 1 from wiki.sources s
                    where s.user_id = d.user_id
                      and s.source_type = 'digest'
                      and s.source_id = d.id::text);
```

Digests aggregate multiple queue items with a human-friendly transcript. Treat the `transcript` as a rich source — often it contains synthesis that single queue items don't. Extract the entities and claims that appear in the transcript but *not* in any individual queue item's fields; those are the high-value candidates. Update existing articles instead of creating new ones when the entity already exists.

### Action items (`content.action_items`)

```sql
select ai.*, c.name as category
  from content.action_items ai
  left join content.action_categories c on c.id = ai.category_id
 where ai.user_id = $user_id
   and not exists (select 1 from wiki.sources s
                    where s.user_id = ai.user_id
                      and s.source_type = 'action_item'
                      and s.source_id = ai.id::text);
```

Most action items are ephemeral (one-off TODOs) and **should not** become articles. The exception: decisions. If an action item is phrased like a decision ("migrate to X", "stop using Y"), create a `type: decision` article with the action's title as the slug base.

### Notion pages

Use Notion MCP search/fetch. Focus on top-level pages and skills pages — the Claude Skills database is a rich source of `tool`-type articles. For each Notion page:
- Dedup via `wiki.find_by_alias` on the page title
- Source identity: Notion page ID

### Claude Code logs (profile-matched)

Logs are JSONL — one object per turn. The signal-to-noise ratio is low at the message level but high at the **decision level**. Filter prompt:

> "Given this Claude Code conversation transcript, extract the decisions, novel insights, and named entities (projects, tools, concepts) that are worth capturing in a personal wiki. Skip tool-call chatter, debugging noise, and restating what already exists in the wiki. Output JSON: `{candidates: [{type, name, summary, justification}]}`. Only emit a candidate if you can state 3+ substantive sentences about it from this conversation."

Scope: `claude_log_personal` → `personal` scope; `claude_log_molt` → `molt` scope, with shared when the content is clearly generic.

### Repos

Walk `README.md`, `CLAUDE.md`, `memory/*.md` files. Each file becomes a `tool` or `project` article (one per repo). Update on subsequent runs when files have changed (compare `mtime` to previous `log_source.ingested_at`).

## Per-candidate flow (same for all sources)

### 1. Scope inference

- Explicit MOLT mention in content → `molt`
- Personal projects (this wiki, finance-tracker, content-queue, Algoritmo-unless-MOLT) → `personal`
- Generic tech → `shared`
- Ambiguous → `shared`

### 2. Dedup via `find_by_alias`

```json
wiki.find_by_alias($user_id, $candidate_name, $candidate_type)
```

- `match = 'exact'` → update path
- `match = 'fuzzy'`, top candidate similarity ≥ 0.55 and same type → update that article
- Otherwise → create new

### 3. Create or update

**3+ substantive sentences rule applies every time.** If you cannot write three substantive sentences from the current source, skip the candidate.

Create:
```json
wiki.upsert_article({
  "user_id": "...",
  "slug": "...",
  "title": "...",
  "type": "concept|person|project|tool|decision",
  "scope": "...",
  "summary": "...",
  "tags": [...],
  "aliases": [...],
  "content_md": "<Wikipedia-tone article with wikilinks>",
  "sources": [{"type": "queue_item|digest|action_item|claude_log_personal|claude_log_molt|repo|notion_skill", "id": "<source id>", "ingested_at": "<iso>"}]
})
```

Update: read the existing article, append a short dated section referencing the new source, call `upsert_article` with merged content. The RPC preserves `manually_edited=true` unless `force=true`.

### 4. Rebuild links

```json
wiki.rebuild_links($article_id)
```

Collect the `missing` slugs. Do not auto-create stubs in MVP; dangling links are `wiki-lint`'s job.

### 5. Log source

Once all candidates from this source item are processed:

```json
wiki.log_source({
  "user_id": "...",
  "source_type": "...",
  "source_id": "<source id>",
  "source_scope": "<dominant scope>",
  "articles_touched": [<every article id touched>]
})
```

Idempotent on `(user_id, source_type, source_id)`. A second run touches nothing.

## Run summary

```
Ingest run — <started_at>
Sources:     <list>
Items read:  <N>  (queue=<q>, digest=<d>, action=<a>, notion=<n>, logs=<l>, repos=<r>)
Articles:    <C> created, <U> updated, <S> skipped (manually_edited)
Links:       <L> added, <M> dangling
Scope mix:   personal=<p>, molt=<m>, shared=<s>
```

Track the ratio of created:updated. A healthy mature wiki skews toward **updated** — more sources strengthening existing articles, fewer new entities per run.

## Calibration

- First run: conservative. If a run creates >2× items processed, tighten the 3+ sentence rule.
- Digest runs typically produce more updates than creates — that's correct; digests are synthesis, not new seeds.
- Claude Code log runs are the noisiest. Start with `--limit=20` and iterate the filter prompt based on what gets rejected in `wiki-lint`.

## Non-goals

- Does not search or answer questions — that is `wiki-ask`.
- Does not delete or merge — that is `wiki-lint`.
- Does not re-process what is already in `wiki.sources` — idempotent by design.
