# Phase 2 — Schema + RPCs

Gate: `wiki.list_index(user_id)` returns an empty array without error.

## Deliverables

- `migrations/001_initial.sql`:
  - `wiki` schema
  - Tables per PLAN.md: `articles`, `links`, `sources`, `aliases`, `corrections`, `retrieval_log`, `rejected_writebacks`, `lint_runs`
  - Indexes: GIN FTS, GIN tags, GIN trigram, btree scope, btree last_retrieved_at
  - Triggers: `updated_at`
- RPCs per PLAN.md §RPCs — all returning `jsonb`, named to mirror `content.*`
- `schema.sql` — full DDL copy for reference
- Extensions: confirm `pg_trgm` available; enable if not

## Open questions to resolve here

- FTS config: `spanish` vs `simple` vs `english` — default `spanish`
- `SECURITY DEFINER` on RPCs? mirror content-queue
- RLS: no (per PLAN.md §Key decisions #14)

## Exit criteria

```sql
SELECT wiki.list_index('<user_id>', NULL);  -- returns []
SELECT wiki.get_user_context('<email>');     -- returns user + prefs jsonb
```

Both succeed against `wjypineoplzwayvktorc`.
