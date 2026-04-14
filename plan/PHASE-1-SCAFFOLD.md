# Phase 1 — Scaffold

Gate: structure created, skill stubs in place, git initialized.

## Deliverables

- [x] Repo root: `CLAUDE.md`, `CLAUDE.local.md`, `README.md`, `config.example.json`, `.gitignore`
- [x] `.claude/settings.json` with Supabase MCP allowances
- [x] `setup/SETUP.md` skeleton
- [x] `skills/wiki-{ingest,ask,lint,review}/SKILL.md` stubs
- [x] `plan/` with PLAN.md and per-phase placeholders
- [x] `migrations/` and `schema.sql` placeholders for Phase 2
- [x] git init + SSH remote to `git@github.com:Ntobon/ai-personal-wiki.git`

## Not yet done (requires user approval)

- Initial commit
- Push to remote
- Install skills into both profiles (`cp -r` to `~/.claude-personal/skills/` and `~/.claude/skills/`)

## Exit criteria

Fresh clone can `cp config.example.json config.json` and read `CLAUDE.md` / `plan/PLAN.md` to understand the project.
