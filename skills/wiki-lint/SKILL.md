---
name: wiki-lint
description: Audit the personal wiki for quality issues — orphans, stale claims, dangling wikilinks, alias collisions, contradictions across articles, and low-confidence write-backs. Use this skill when the user says "/wiki-lint", "audit the wiki", "check wiki health", "lint the wiki", on scheduled weekly runs, or after a large ingest. Writes findings to wiki.lint_runs and proposes fixes; applies only those the user explicitly approves.
platform: both
version: 0.2.0
---

# wiki-lint

Batched audit. Never auto-applies destructive fixes; always produces a proposal the user can approve.

## Bootstrap

1. Resolve project + user (same pattern as other wiki-* skills).
2. Open a `wiki.lint_runs` row at the start, close it at the end with findings + fixes_applied.

```sql
insert into wiki.lint_runs (user_id) values ($user_id) returning id;
-- ... run checks ...
update wiki.lint_runs set finished_at = now(), findings = $findings, fixes_applied = $fixes where id = $run_id;
```

## Checks

Each check produces entries shaped as:

```json
{"kind": "orphan|dangling_link|stale|alias_collision|contradiction|lowconf_writeback|never_retrieved",
 "article_id": "...", "slug": "...", "detail": "...", "suggested_fix": "..."}
```

### 1. Orphans

```sql
wiki.orphans(user_id)
```
Articles with no inbound or outbound links. For each:
- If `created_at < now() - interval '30 days'` and `last_retrieved_at is null`: propose merge-or-delete.
- Otherwise: suggest adding at least one wikilink and re-running `wiki.rebuild_links`.

### 2. Dangling wikilinks

```sql
with refs as (
  select a.id as from_id, lower(trim(split_part(m[1], '|', 1))) as slug
  from wiki.articles a,
       regexp_matches(a.content_md, '\[\[([^\]]+)\]\]', 'g') m
  where a.user_id = $user_id
)
select r.from_id, r.slug as missing_slug
from refs r
left join wiki.articles target
  on target.user_id = $user_id and target.slug = r.slug
where target.id is null;
```

For each missing slug, suggest one of:
- Create a stub article for it, with a TODO marker
- Rewrite the link to an existing similar slug (trigram-match against `wiki.articles.title`)
- Remove the link

### 3. Stale content

- `last_retrieved_at < now() - interval '90 days'` and `last_manual_edit_at is null` → candidate for prune.
- `last_retrieved_at is null` and `created_at < now() - interval '30 days'` → never read since birth; candidate for delete if also unlinked.

### 4. Alias collisions

```sql
with expanded as (
  select id, slug, title, lower(unnest(aliases || array[title])) as name, type
  from wiki.articles where user_id = $user_id
)
select name, type, array_agg(slug) as slugs
from expanded
group by name, type
having count(*) > 1;
```
Same alias pointing to multiple articles of the same type → propose merge.

### 5. Contradictions (expensive)

For each pair of articles that share ≥ 2 tags OR link to each other, run a parallel subagent (batches of 5 pairs at a time) with prompt:

> "Compare these two wiki articles. Report any factual contradictions — dates, attributions, claims about the same entity. If none, answer `no contradictions`. Output JSON: `{contradictions: [{article_a_claim, article_b_claim, confidence}]}`."

Only run this check when explicitly requested (`/wiki-lint --deep`) or on monthly scheduled runs — it's the expensive one.

### 6. Low-confidence write-backs

```sql
select id, slug, sources
from wiki.articles
where user_id = $user_id
  and sources @> '[{"type":"ask_writeback"}]'::jsonb
  and jsonb_path_exists(sources, '$[*] ? (@.type == "ask_writeback" && @.confidence == "low")');
```
Suggest: merge with a higher-confidence article, delete, or mark for manual review.

### 7. Never-retrieved + unused

`last_retrieved_at is null and created_at < now() - interval '60 days'` — article was created and never read.

## Proposal output

Render a single markdown summary:

```markdown
## Lint findings — <date>, <N> issues

### Orphans (<k>)
- [[slug-a]] — created 40 days ago, never retrieved. Propose: delete unless you object.
- [[slug-b]] — 5 days old, no links. Propose: add wikilinks from related articles.

### Dangling wikilinks (<k>)
- [[article-x]] → `[[personal-wiki]]` (missing). Propose: create stub.

### Stale (<k>)
- [[slug-c]] — last retrieved 120 days ago, last edit never. Propose: prune.

### Alias collisions (<k>)
- `alex` → [[alex-cliente-molt]] and [[alex-ramirez]]. Propose: rename aliases to disambiguate.

### Contradictions (<k>, `--deep` only)
- [[a]] says X released in 2024; [[b]] says X released in 2025. Confidence: high.

### Low-confidence write-backs (<k>)
- [[slug-d]] — ask_writeback, confidence low. Propose: merge with [[slug-e]].

## Apply?
(y) apply all safe fixes
(n) cancel
(s) cherry-pick — ask per finding
```

## Applying fixes

- `y` — run all fixes that are tagged `safe` (add wikilink, create stub from dangling, rename alias). Never auto-delete.
- `s` — iterate with the user, one finding at a time.
- `n` — close the `lint_runs` row with `fixes_applied: {}`.

Even with `y`, deletes require explicit "delete [[slug]]" confirmation from the user.

## Exit

Close the `lint_runs` row:
```sql
update wiki.lint_runs
   set finished_at = now(),
       findings = $findings_jsonb,
       fixes_applied = $fixes_jsonb
 where id = $run_id;
```

Then print a one-line summary:
```
Lint complete. <N> findings, <K> fixes applied, <D> deferred. See wiki.lint_runs.<id>.
```

## Calibration

- First run on a new wiki will have many orphans — that's expected; don't prune aggressively.
- After a large ingest, only care about orphans and dangling links; defer contradictions until the wiki stabilizes.
- The `--deep` flag (contradictions) is for monthly use, not per-run.
