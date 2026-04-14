---
name: wiki-ingest
description: Pull from reading queue, digests, action items, Claude Code logs (both profiles), Notion, and repos; compile into wiki articles. Use this skill when the user says "/wiki-ingest", "compile wiki", "ingest into wiki", "actualizar wiki", or on scheduled runs. Segments sources by platform — cloud sources run everywhere; local sources (Claude Code logs, repos) only run in the matching profile.
platform: both
version: 0.1.0
---

# wiki-ingest

**STUB — Phase 3 deliverable.** Not yet functional.

## Intended behavior

Pull-based compile. Triggers: `/wiki-ingest`, "compile wiki", scheduled runs.

### Sources

**Cloud-accessible (any profile, mobile):**
- `content.queue_items`, `content.digests`, `content.action_items`
- Notion (personal + MOLT workspaces where available)

**Local-only (matching profile):**
- `~/.claude-personal/projects/*.jsonl` (Personal profile logs)
- `~/.claude/projects/*.jsonl` (MOLT profile logs)
- `~/personal/*` and `~/molt/*` repos (READMEs, CLAUDE.md, memory files)

### Flow

1. Bootstrap (config → memory → `wiki.get_user_context`)
2. Detect platform; for each accessible source, query "new since last `wiki.log_source`"
3. Bucket raw material chronologically
4. Per entry: infer `scope` (personal / molt / shared), then `wiki.find_by_alias`
5. **Hard rule: 3+ substantive sentences or no article is created**
6. Inline lint:
   - Trigram match against existing before create (dedup)
   - `rebuild_links` after write
   - Flag obvious contradictions with existing articles
7. Preserve `manually_edited=true` unless explicit override
8. `wiki.log_source` at end — idempotent on replay

## Implementation

TBD.
