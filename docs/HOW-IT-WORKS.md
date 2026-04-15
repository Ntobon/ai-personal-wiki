# How the personal-wiki works

A Karpathy-style, LLM-native personal wiki. No human UI. Four Claude skills and one MCP proxy talk to a Postgres schema on Supabase. Every interaction goes through stored functions — skills never touch tables directly.

## The three ops

Everything the wiki does is one of:

1. **Ingest** — pull raw material from existing sources, extract worth-an-article entities, and write them as articles.
2. **Query** — search the wiki, read full articles, synthesize grounded answers, and optionally write new insights back.
3. **Lint** — audit for quality issues (orphans, dangling links, stale claims, contradictions, low-confidence write-backs).

A monthly **review** rolls the three ops into an actionable report.

## Data model

All articles live in the `wiki` schema inside the shared Supabase project `wjypineoplzwayvktorc`. `content.users.id` is the single identity — the wiki's `articles.user_id` FKs into it.

```
wiki.articles           one article per entity (person, project, concept, decision, tool)
wiki.links              precomputed outbound/backlink graph
wiki.sources            ingest log, idempotency key (user_id, source_type, source_id)
wiki.corrections        user corrections, optionally applied to article content
wiki.retrieval_log      every search call, for hit-rate analysis
wiki.rejected_writebacks   write-backs the user declined, for calibration
wiki.lint_runs          historical findings and fixes
```

Articles carry `type` (person / project / concept / decision / tool), `scope` (personal / molt / shared), and a `tsvector search_vector` generated from title + aliases + summary + tags + content_md with per-field weights. Retrieval is Postgres FTS with a trigram fallback — no chunking, no embeddings in v1.

The architecture diagram:

```
 ┌──────────────────────────────────┐
 │  Claude skills (SKILL.md files)  │
 │  wiki-ingest  wiki-ask           │
 │  wiki-lint    wiki-review        │
 └──────────────┬───────────────────┘
                │ calls
 ┌──────────────▼───────────────────┐
 │  Transport layer                 │
 │  Personal/Mobile: Supabase MCP   │
 │  MOLT profile:    wiki-proxy MCP │◄── stdio, TypeScript,
 └──────────────┬───────────────────┘      routes to Supabase
                │
 ┌──────────────▼───────────────────┐
 │  public.wiki_* wrappers          │  SECURITY DEFINER, reachable via REST
 └──────────────┬───────────────────┘
                │
 ┌──────────────▼───────────────────┐
 │  wiki.* functions (real logic)   │  13 stored functions
 └──────────────┬───────────────────┘
                │
 ┌──────────────▼───────────────────┐
 │  wiki.* tables (FTS + trigram)   │
 └──────────────────────────────────┘
```

## Transport: why two paths

Supabase's official MCP is **single-org**. The MOLT Claude Code profile already has a Supabase MCP scoped to the MOLT organisation and cannot add a second Supabase MCP for the personal organisation where this wiki lives.

Solution: **`wiki-proxy/`** — a tiny stdio MCP server written in TypeScript. It exposes 13 `wiki_*` tools that delegate to `public.wiki_*` wrappers via supabase-js. MOLT profile points at `wiki-proxy` in its `.mcp.json`; personal profile and claude.ai mobile use the official Supabase MCP. Skills detect profile at runtime and pick the right transport.

Why `public.wiki_*` wrappers? PostgREST only exposes schemas listed in the project's `db-schemas` config (default: just `public`). Rather than fight that, the wrappers are thin `SECURITY DEFINER` SQL functions with a locked `search_path` — the caller never needs `USAGE` on the `wiki` schema.

## The ingest flow

Triggered by `/wiki-ingest` or on a cron schedule. The skill:

1. **Bootstraps** — resolve `user_id` via `wiki.get_user_context(email)`.
2. **Picks sources** — cloud sources (reading queue, digests, action items, Notion) run from any profile or mobile; local-filesystem sources (Claude Code logs, repos) only run in the matching profile.
3. **Pulls new material** — `WHERE NOT EXISTS (SELECT 1 FROM wiki.sources WHERE ...)` keeps replay idempotent.
4. **Extracts entities** — a queue item is raw material, not an article. The skill extracts multiple worth-an-article entities from each item (person, project, concept, tool, decision). The **3+ substantive sentences rule** is hard: if you can't write three real sentences about a candidate, skip it.
5. **Dedups** — `wiki.find_by_alias(user_id, name, type)` does exact match (slug / title / alias) then trigram fuzzy. A similarity ≥ 0.55 on the same type is treated as a dedup hit.
6. **Writes** — `wiki.upsert_article(payload)` creates or updates. `manually_edited=true` articles are preserved unless `force=true`.
7. **Rebuilds links** — `wiki.rebuild_links(article_id)` parses `[[wikilinks]]` from the article's content and refreshes `wiki.links`. Missing targets are surfaced in the return value but not auto-created; they're `wiki-lint`'s job.
8. **Logs the source** — `wiki.log_source({...})`. The unique constraint `(user_id, source_type, source_id)` means a second `/wiki-ingest` on the same material changes nothing.

Target ratio: **~1.5–2 articles per queue item**. Digests typically produce more updates than creates (they're synthesis, not seeds). Log runs are the noisiest — the skill filters to "decisions and novel insights" and defers the rest.

## The query flow

Triggered by questions with personal context — "what do we know about X", "ask the wiki", "qué sabemos de Y".

1. **Search** — `wiki.search(user_id, query, scope, 5)`. FTS primary; trigram fallback picks up typos and variants FTS misses. Every call is auto-logged to `wiki.retrieval_log`, which powers the monthly review.
2. **Read** — for each of the top ~3 hits, `wiki.read_article(user_id, slug)` returns the full content plus outbound and backlink neighbours. Budget: five reads per question.
3. **Synthesize** — Wikipedia tone. Every claim traces to a slug. Uncertainty is explicit. If the wiki is thin on a topic, the skill says so rather than hallucinating.
4. **Correction detection** — if the next user turn negates something ("no, actually X", "estás equivocado"), the skill calls `wiki.record_correction(...)`. With `apply_to_article=true` the correction rewrites the matching substring in the article's `content_md`.
5. **Write-back** — if synthesis produced genuinely new connections, the skill asks once: "archive this?" On yes, `wiki.upsert_article` with `sources: [{type: 'ask_writeback', ...}]`. On no, `wiki.reject_writeback(...)` logs the pattern for calibration.

At MVP the write-back default is **ask before archiving**. Once heuristics prove out over weeks, it can shift toward auto-archive for high-confidence cases — but only on explicit user approval.

## The lint flow

Triggered by `/wiki-lint` weekly (via `/schedule`) or after a large ingest. Opens a `wiki.lint_runs` row, runs checks, closes it with findings + applied fixes.

Checks:

- **Orphans** (`wiki.orphans(user_id)`) — articles with zero inbound and zero outbound links.
- **Dangling wikilinks** — a regex scan for `[[slug]]` pointing at non-existent slugs.
- **Stale content** — `last_retrieved_at` older than 90 days with no manual edits.
- **Alias collisions** — same alias pointing at multiple articles of the same type.
- **Contradictions** (opt-in `--deep`) — parallel subagents compare pairs that share tags or link to each other. This is the expensive check; monthly only.
- **Low-confidence write-backs** — articles whose sources include `ask_writeback` with `confidence: low`.

Output is a single markdown proposal. Apply modes: `y` (all safe fixes), `s` (cherry-pick per finding), `n` (cancel). Deletes always require explicit confirmation — no matter the apply mode.

## The monthly review

`/wiki-review` assembles:

- **Growth** — articles created / updated, links delta, sources ingested by type.
- **Usage** — total queries, hit rate, top-5 most-asked topics, top-5 zero-result queries.
- **Feedback signal** — corrections by channel (wiki-ask vs manual), top 3 correction narratives, rejected write-backs and the top rejection reason.
- **Health** — pulled from `wiki.lint_summary(user_id)` — orphans, stale, never-retrieved, 30-day correction/rejection counts.
- **Top-5 actionable findings** — prioritized by expected value: zero-result queries with volume beat cosmetic dangling links.

Optionally saves itself as a `manually_edited=true` wiki article (`wiki-review-2026-04` etc.). Future queries like "how has the wiki changed in 2026?" then return real answers.

## Scope

Every article has a `scope`: `personal`, `molt`, or `shared`. Inferred at ingest time:

- Explicit MOLT mention → `molt`
- Personal projects (this wiki, finance-tracker, content-queue, etc.) → `personal`
- Generic tech → `shared`
- Ambiguous → `shared` (always safe; corrected later via `/wiki-lint`)

Logs in `~/.claude/projects/*` are `molt`-scoped by default; logs in `~/.claude-personal/projects/*` are `personal`. Mobile queries see everything filtered by scope at query time.

## Scheduling

Cloud-only ops run via Anthropic CCR triggers (self-contained prompts, Supabase MCP attached). Times chosen to land during the work window (Mon–Fri, America/Bogota):

| Schedule | Cron (UTC) | Bogota | Purpose |
|---|---|---|---|
| Daily cloud ingest | `0 14 * * 1-5` | Mon–Fri 09:00 | queue + digests + actions |
| Weekly lint | `0 15 * * 1` | Mon 10:00 | orphans / dangling / stale / collisions |
| Monthly review | `0 16 1 * *` | 1st 11:00 | Top-5 actionable, saved as wiki article |

Local-filesystem ingest (Claude Code logs, repos) requires a live profile — remote triggers can't reach `~/.claude-personal/projects/*` or your repo tree. Either a `Stop` hook in each profile's `settings.json` (auto-fires after each session) or manual `ccp /wiki-ingest --sources=logs,repos`. Start manual until the filter prompt is dialed in — then move to the hook.

## Feedback loops, briefly

Five loops keep the wiki self-correcting:

1. **Conversational corrections** → `wiki.corrections`. The article rewrites immediately when the match is unambiguous.
2. **Retrieval misses** → `wiki.retrieval_log`. Monthly review flags zero-result queries as signal of missing sources.
3. **Usage-based pruning** → `last_retrieved_at`. Lint candidates stale articles for merge or delete.
4. **Write-back calibration** → `wiki.rejected_writebacks`. Lint audits low-confidence write-backs and patterns in rejections tune the prompt.
5. **Monthly meta-loop** → `wiki-review` surfaces patterns across all four loops and proposes prompt or schedule changes.

## File map

```
migrations/
  000_local_content_stub.sql   # idempotent content.users stub (local only)
  001_initial.sql              # wiki tables, indexes, tsv_build, updated_at trigger
  002_rpcs.sql                 # 13 wiki.* stored functions
  003_public_wrappers.sql      # 13 public.wiki_* SECURITY DEFINER wrappers

skills/
  wiki-ingest/SKILL.md         # compile raw sources into articles
  wiki-ask/SKILL.md            # query + synthesis + correction + write-back
  wiki-lint/SKILL.md           # batched audit + proposed fixes
  wiki-review/SKILL.md         # monthly actionable report

wiki-proxy/                    # TS stdio MCP server (for MOLT profile)
  src/config.ts                # env + file config loader
  src/supabase.ts              # supabase-js wrapper, public.wiki_* dispatcher
  src/tools.ts                 # 13 tool definitions with JSON schemas
  src/index.ts                 # MCP server entry
  bin/server                   # ESM launcher (node shebang)
  scripts/smoke.js             # speaks MCP stdio, validates end-to-end

tests/                         # SQL test suites (DO $$ ASSERT $$; BEGIN/ROLLBACK)
docker-compose.yml             # local Postgres 17 with pg_trgm
Makefile                       # up / down / reset / migrate / test / psql
plan/PLAN.md                   # original plan, kept for reference
plan/PHASE-*.md                # per-phase status and gates
```

## Daily operation

One-line summaries of the agent experience:

- **Capture new material:** `/wiki-ingest` (or a scheduled run) pulls new queue items, digests, actions, logs. Produces articles silently.
- **Ask a question:** "what do we know about X?" triggers `wiki-ask`. Grounded answer with slug citations. Corrections are captured automatically.
- **Clean up:** `/wiki-lint` (weekly) surfaces issues and asks before applying.
- **See what changed:** `/wiki-review` (monthly) — one report, top-5 actions, done in a minute.

No human UI is ever rendered. The wiki is a substrate for agent cognition, not a product.
