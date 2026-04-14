# personal-wiki

Karpathy-style LLM-native personal wiki. Built on Supabase FTS, consumed by Claude Code (both profiles) and claude.ai. No human UI — agents read, write, and lint.

## What this is

Three ops power everything:
- **Ingest** — pull from reading queue, digests, action items, Claude Code logs (both profiles), Notion, repos. Update existing articles; create new only with substance.
- **Query** — agent searches the wiki, reads full articles, answers, and writes insights back as new articles or sections. Self-compacting loop.
- **Lint** — cheap inline checks on every write + batched audit (contradictions, orphans, stale, broken links).

Retrieval is Postgres FTS over whole articles. No chunking, no embeddings in v1. pgvector stays on the shelf until FTS proves insufficient.

## Supabase

- Project `wjypineoplzwayvktorc` (shared with `content-queue`, `finance-tracker`)
- Schema `wiki` (isolated from `content.*` and `public.*`)
- FK to `content.users(id)` — single user identity across personal projects

## Setup

See `setup/SETUP.md`. In short:

1. Copy `config.example.json` → `config.json`, fill in your email
2. Apply migrations in `migrations/`
3. Install skills into both `~/.claude-personal/skills/` and `~/.claude/skills/`
4. Configure MCPs in both profiles (Supabase MCP + `wiki-proxy` for MOLT)

## Skills

| Skill | Purpose |
|-------|---------|
| `wiki-ingest` | Pull from sources, compile into articles |
| `wiki-ask` | Query with write-back and correction detection |
| `wiki-lint` | Batched audit |
| `wiki-review` | Monthly actionable report |

## Docs

- `docs/HOW-IT-WORKS.md` — architecture, data model, transport, flows, feedback loops.

## Plan

`plan/PLAN.md` has the original plan; per-phase status lives in `plan/PHASE-*.md` and `CLAUDE.md`.
