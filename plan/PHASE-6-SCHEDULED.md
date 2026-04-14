# Phase 6 — Scheduled triggers

Use Claude's `/schedule` system for cloud-only ingests and lints. Local-filesystem ingests (Claude Code logs, repos) require a running profile, so wire them via a `Stop` hook or by manual invocation.

## Cloud-only schedules (via `/schedule`)

Run these from any profile — they touch only `content.*` (queue, digests, actions) and `wiki.*`.

### Daily ingest

```
/schedule create
  name: wiki-daily-cloud-ingest
  cron: 0 6 * * *         # 06:00 local
  prompt: /wiki-ingest --sources=queue,digests,actions
```

### Weekly lint

```
/schedule create
  name: wiki-weekly-lint
  cron: 0 7 * * 1         # Monday 07:00
  prompt: /wiki-lint
```

### Monthly review

```
/schedule create
  name: wiki-monthly-review
  cron: 0 8 1 * *         # 1st of month, 08:00
  prompt: /wiki-review
```

List / edit / remove via `/schedule list` etc. Each scheduled run is a fresh conversation; the skills bootstrap from `personal-wiki/config.json` or memory, so no extra params are needed.

## Local-source ingests (per profile)

Claude Code logs and repos live on the filesystem. Two options:

### Option A: Stop hook (zero-touch)

Add to the profile's `settings.json` (personal or MOLT):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "echo '/wiki-ingest --sources=logs,repos --limit=20' | claude --profile personal --print" }
        ]
      }
    ]
  }
}
```

Runs after each Claude Code session ends, limited to 20 candidates to stay cheap. The matching profile decides which log directory to read — personal profile ingests `~/.claude-personal/projects/*.jsonl`; MOLT profile ingests `~/.claude/projects/*.jsonl`.

**Cost control:** `--limit=20` keeps the hook bounded. Without a limit, an active development day could pull hundreds of log turns.

### Option B: Manual

```bash
ccp /wiki-ingest --sources=logs,repos   # from personal profile
ccd /wiki-ingest --sources=logs,repos   # from MOLT profile
```

Start with Option B to see what the ingest does; move to Option A once confidence is high.

## Scope auto-inference

Logs from `~/.claude-personal/projects/*` → `personal`.
Logs from `~/.claude/projects/*` → `molt`.
Generic technical content extracted from logs → `shared` (the compile prompt decides).

## Non-schedulable work

- `/wiki-ask` is interactive by nature — never schedule it.
- `wiki-proxy` runs on demand when the MOLT profile invokes a `wiki_*` tool; no scheduling required.

## Monitoring

After each scheduled run, the skill writes to `wiki.sources` (ingest) or `wiki.lint_runs` (lint). Query:

```sql
select source_type, count(*), max(ingested_at) as last_run
from wiki.sources
where user_id = $user_id
group by source_type;
```

Ties into the monthly `/wiki-review` output — the review will surface any schedule that has stopped firing.
