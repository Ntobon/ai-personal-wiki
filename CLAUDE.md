# Personal Wiki

## Git — STRICT RULES
- **NEVER commit** without explicit user permission. Always ask before committing.
- **NEVER push to remote** without explicit user permission. Always ask before pushing.
- Do NOT combine commit + push in one step. Commit first, then ask separately about pushing.

## Overview

Karpathy-style LLM-native wiki in Supabase. Consumed by agents (Claude Code both profiles, claude.ai mobile/web). **No human UI.** Three ops: ingest, query (with write-back), lint. Postgres FTS over whole articles — no chunking, no embeddings in v1.

Mirrors `content-queue` conventions.

## Architecture

- **Database**: Supabase project `wjypineoplzwayvktorc` (shared with content-queue, finance-tracker), schema `wiki`
- **Retrieval**: Postgres FTS (`tsvector` + `pg_trgm`) over full articles. pgvector deferred to phase-2 if FTS underperforms.
- **Transport**: Personal profile / mobile → Supabase MCP (personal org). MOLT profile → `wiki-proxy` MCP (custom stdio server in `wiki-proxy/`) because Supabase MCP is single-org and MOLT profile's MCP already points at MOLT org.
- **Scope field** on every article: `personal | molt | shared`. Filter on queries; tag on ingest.
- **Tone**: Wikipedia, not AI voice. Short sentences. Attribution over assertion. Max 2 direct quotes per article.

## Configuration resolution

1. Read `config.json` in this repo (if working from this directory)
2. Check Claude memory for `wiki_project_id` and `user_email`
3. Ask the user and store appropriately

## Bootstrap sequence

Every conversation that touches the wiki:
1. Resolve `supabase_project_id` and `user_email`
2. Call: `SELECT wiki.get_user_context('<email>')`
3. Cache: `user_id`, scope preference, recent ingests
4. Process the user's request

## Supabase project

- **Project ID**: `wjypineoplzwayvktorc` (same as content-queue, finance-tracker)
- **Schema**: `wiki` (NOT public — kept separate from `content.*` and `public.*`)
- All queries must use `wiki.` prefix for tables and functions
- FK: `wiki.articles.user_id` references `content.users(id)` — single source of user identity across projects

## Skills

| Skill | Purpose | Platform | Status |
|-------|---------|----------|--------|
| wiki-ingest | Pull from queue/digests/actions/logs/repos, compile into articles | both | stub (Phase 3) |
| wiki-ask | Query + write-back + correction detection | both | stub (Phase 4) |
| wiki-lint | Contradictions, orphans, stale claims, broken links | both | stub (Phase 5) |
| wiki-review | Monthly actionable report | both | stub (Phase 10) |

### Editing skills

**Always edit skills in this repo** (`skills/` directory), then copy to the active location(s):
```bash
cp -r skills/<name>/ ~/.claude-personal/skills/<name>/
cp -r skills/<name>/ ~/.claude/skills/<name>/
```
This repo is the source of truth. After editing, push to Notion via `/skill-push`.

## Platform awareness

| Capability | Personal (`~/.claude-personal`) | MOLT (`~/.claude`) | Mobile/Web |
|---|---|---|---|
| Supabase MCP → personal org | yes | blocked (on MOLT org) | yes |
| wiki-proxy MCP (stdio) | optional | **only access path** | no (no stdio in cloud) |
| Filesystem (logs, repos) | `~/.claude-personal/*` | `~/.claude/*` | no |
| Scheduled triggers | `/schedule` | `/schedule` | `/schedule` |

Skills detect profile at runtime and pick the transport. Ingest fuentes are partitioned the same way: cloud sources work everywhere; local sources (Claude Code logs, repos) only work in the matching profile.

## Stored functions (see `schema.sql`)

| Function | Purpose |
|----------|---------|
| `wiki.get_user_context(email)` | Bootstrap — user + scope prefs + recent ingests |
| `wiki.list_index(user_id, scope)` | Lightweight index: slug + title + summary + tags |
| `wiki.read_article(user_id, slug)` | Full article + outbound links + backlinks; bumps `last_retrieved_at` |
| `wiki.search(user_id, query, scope, limit)` | FTS + trigram fallback; logs to `retrieval_log` |
| `wiki.find_by_alias(user_id, name, type?)` | Dedup lookup during ingest |
| `wiki.upsert_article(...)` | Compile step writes here; preserves `manually_edited=true` unless forced |
| `wiki.rebuild_links(article_id)` | Scan `[[wikilinks]]`; refresh `wiki.links` |
| `wiki.log_source(...)` | Record ingest; idempotency key |
| `wiki.recent_ingests(user_id, limit)` | Chronological compile activity |
| `wiki.orphans(user_id)` | Articles with no inbound or outbound links |
| `wiki.record_correction(...)` | Apply user correction; update article + log |
| `wiki.reject_writeback(...)` | Record rejected write-back for learning |
| `wiki.lint_summary(user_id)` | Latest lint findings + health metrics |

All return `jsonb`. Naming mirrors `content.*`.

Every `wiki.*` RPC also has a `public.wiki_<fn>` wrapper (`SECURITY DEFINER`, locked `search_path`) so PostgREST can reach them via the default REST surface. The `wiki-proxy` MCP server calls the public wrappers.

## Local development

Full local stack via docker-compose — Postgres 17 with migrations auto-applied.

```bash
make up        # start Postgres
make migrate   # apply migrations/*.sql in order
make test      # run all tests/*.sql against a fresh db (resets + migrates + runs)
make psql      # open a shell
make down      # stop (keep volume)
make reset     # drop volume + restart + migrate
```

The local DB runs on port `5433` (to avoid colliding with any system Postgres on 5432). Credentials: `wiki/wiki`, database `wiki`.

`migrations/000_local_content_stub.sql` creates a minimal `content.users` table locally. In prod (`wjypineoplzwayvktorc`) this already exists; the CREATE IF NOT EXISTS guards make the migration a no-op.

## Phase status

See `plan/PLAN.md` for full plan.

| Phase | What | Status |
|---|---|---|
| 1 | Scaffold | done |
| 2 | Schema + RPCs | done (local + prod) |
| 2b | wiki-proxy MCP server | done (TS stdio, smoke-tested against prod) |
| 3 | wiki-ingest MVP (queue items only) | done; 6 articles live in prod |
| 4 | wiki-ask query + write-back | done (skill v0.2.0) |
| 5 | wiki-lint batched audit | done (skill v0.2.0) |
| 6 | Scheduled triggers | documented (`plan/PHASE-6-SCHEDULED.md`) |
| 7-9 | Ingest expansion (digests, actions, logs, Notion, repos) | documented in wiki-ingest v0.4.0 |
| 10 | wiki-review monthly | done (skill v0.2.0) |
