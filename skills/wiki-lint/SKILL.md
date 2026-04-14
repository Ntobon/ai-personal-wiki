---
name: wiki-lint
description: Batched audit of the wiki — detects contradictions across articles, orphans, stale claims, alias collisions, broken wikilinks, and low-confidence write-backs. Use this skill when the user says "/wiki-lint", "audit the wiki", "check wiki health", on weekly scheduled runs, or after a large ingest. Writes findings to wiki.lint_runs and proposes fixes.
platform: both
version: 0.1.0
---

# wiki-lint

**STUB — Phase 5 deliverable.** Not yet functional.

## Intended behavior

### Checks

- Cross-article contradictions (parallel subagents, batches of 5)
- Orphans (`wiki.orphans`)
- Stale claims (articles not updated in 6+ months but sources still referenced)
- Alias collisions
- Broken `[[wikilinks]]`
- Low-confidence write-backs → propose merge or delete
- Articles with `last_retrieved_at` > 3 months → prune candidates

### Output

Writes findings to `wiki.lint_runs`. Proposes fixes; applies high-confidence fixes if user approves the batch.

## Implementation

TBD.
