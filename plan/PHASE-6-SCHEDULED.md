# Phase 6 — Scheduled triggers

Use Claude's `/schedule` system for cloud-only ingests and lints. Local-filesystem ingests (Claude Code logs, repos) require a running profile, so wire them via a `Stop` hook or by manual invocation.

## Cloud-only schedules (registered with Anthropic CCR)

These run in Anthropic's cloud — no local machine needed. Aligned to the user's work window (America/Bogota, UTC-5), so output lands during the day.

| Trigger | ID | Cron (UTC) | Bogota |
|---|---|---|---|
| `wiki-daily-cloud-ingest` | `trig_01F6TD9WDVAGwY5NkUf6jGGW` | `0 14 * * 1-5` | Mon–Fri 09:00 |
| `wiki-weekly-lint` | `trig_01HiU3kiysjD4k6xaF7XuDwv` | `0 15 * * 1` | Mon 10:00 |
| `wiki-monthly-review` | `trig_01TiAPb2Z44opwFU846dNYiC` | `0 16 1 * *` | 1st 11:00 |

Prompts are fully self-contained — no git checkout, no config.json. User ID is looked up at runtime via `public.wiki_get_user_context('nicolastoboncastano@gmail.com')` over the attached Supabase MCP.

Manage at https://claude.ai/code/scheduled. Deletes only via the UI (API doesn't support delete).

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
