---
name: wiki-review
description: Generate a monthly actionable review of the personal wiki — corrections, rejected write-backs, retrieval misses, health metrics, and top-5 findings with proposed fixes. Use this skill when the user says "/wiki-review", "wiki health report", "monthly wiki review", "reporte del wiki", or on scheduled monthly runs. Produces a focused report the user can act on, not a vanity dashboard.
platform: both
version: 0.2.0
---

# wiki-review

Monthly roll-up of the feedback tables. Answers: what is the wiki learning, what is it getting wrong, and what should change this month?

## Bootstrap

Same pattern as other wiki-* skills. Default window is the last 30 days; user may pass a different window ("last week", "since last review").

## Data pulled

All queries filter by `user_id` and the window.

### Corrections (what compile got wrong)

```sql
select detected_in, count(*) as n,
       array_agg(distinct article_id) filter (where article_id is not null) as articles
from wiki.corrections
where user_id = $user_id and corrected_at > $window_start
group by detected_in
order by n desc;
```

Also pull the 5 most recent corrections in full for the narrative.

### Rejected write-backs (what the user said not to archive)

```sql
select proposed_content, rejection_reason, rejected_at
from wiki.rejected_writebacks
where user_id = $user_id and rejected_at > $window_start
order by rejected_at desc
limit 20;
```

Look for patterns in `rejection_reason` — are there recurring reasons ("too speculative", "already covered", "not useful")? Those patterns are the signal for adjusting the `wiki-ask` write-back prompt.

### Retrieval log (what the user asked)

```sql
select
  count(*) as total_queries,
  count(*) filter (where results_count = 0) as zero_result_queries,
  count(*) filter (where results_count > 0) as hit_queries
from wiki.retrieval_log
where user_id = $user_id and asked_at > $window_start;

-- top zero-result queries for signal
select query, count(*) as n
from wiki.retrieval_log
where user_id = $user_id and asked_at > $window_start and results_count = 0
group by query
order by n desc
limit 10;
```

### Health metrics

```sql
select wiki.lint_summary($user_id);
```

Plus:
```sql
select
  count(*) as total_articles,
  count(*) filter (where created_at > $window_start) as created_this_window,
  count(*) filter (where updated_at > $window_start and created_at <= $window_start) as updated_this_window,
  count(*) filter (where manually_edited) as manually_edited,
  count(*) filter (where last_retrieved_at > now() - interval '30 days') as retrieved_30d
from wiki.articles
where user_id = $user_id;
```

### Top articles by retrieval

```sql
select a.slug, a.title, count(*) as retrievals
from wiki.retrieval_log rl
join lateral unnest(rl.articles_returned) ret on true
join wiki.articles a on a.id = ret
where a.user_id = $user_id and rl.asked_at > $window_start
group by a.slug, a.title
order by retrievals desc
limit 10;
```

## Report format

```markdown
# Wiki review — <window label>

## Growth
- Articles: <total> total (+<created> this window, <updated> updated)
- Links: <link_count> (+<delta>)
- Sources ingested: <count> (queue=<q>, digest=<d>, action=<a>, logs=<l>)

## Usage
- Queries: <total>, hit rate <hit_rate>%
- Most-asked topics: <top 5 slugs by retrieval count>
- Zero-result queries: <top 5>

## Feedback signal
- Corrections: <n> (<wiki-ask: X, manual: Y>)
- Top 3 corrections (narrative): <list>
- Rejected write-backs: <n> (<top reason: ...>)

## Health (via wiki.lint_summary)
- Orphans: <n>
- Stale (90d): <n>
- Never retrieved: <n>
- Corrections (30d): <n>, Rejected (30d): <n>

## Top-5 actionable findings
1. **<issue>** — <proposed fix> (expected effort: low/med/high)
2. ...

## Suggested next actions
- Run `/wiki-lint --deep` if contradiction signal is high.
- Adjust the ingest prompt if a specific source-type is producing too many rejected write-backs.
- Add new fuentes (Notion? repos?) if zero-result queries point to a specific gap.
```

## Top-5 prioritization

Rank findings by expected value:

1. **Zero-result queries with volume** → missing sources; highest leverage because every future query benefits.
2. **Patterns in corrections** → the ingest prompt is wrong; fixing it prevents future bad articles.
3. **High retrieval + stale** → core articles aging out; refresh is worth it.
4. **Orphans that keep accumulating** → ingest is over-extracting; tighten the rules.
5. **Dangling wikilinks** → cosmetic but cheap to fix.

Rejected-writeback patterns rarely make top-5 unless they're dominant (>50% of write-backs being rejected means the threshold is wrong).

## Non-goals

- This is not a lint runner — don't re-do `wiki-lint`'s work. Pull `wiki.lint_summary` and link to the latest `wiki.lint_runs` row.
- This is not a cron job — a human or the `/schedule` system triggers it.
- Not a correction reviewer — corrections are handled inline in `wiki-ask`.

## Output delivery

Default: render the report inline to the user. If the user says "save the review", write it as a manually-edited article:

```json
wiki.upsert_article({
  "user_id": "...",
  "slug": "wiki-review-2026-04",
  "title": "Wiki review — April 2026",
  "type": "decision",
  "scope": "personal",
  "manually_edited": true,
  "summary": "Monthly wiki review: ...",
  "content_md": "<the report>"
})
```

This makes past reviews themselves searchable via the wiki — you can ask "how has the wiki changed in 2026?" and get a real answer.
