---
name: wiki-ask
description: Query the wiki with write-back and correction detection. Use this skill when the user asks questions with personal context — "what do we know about X", "ask the wiki", "qué sabemos de Y", or any query that should be grounded in previously ingested knowledge. Synthesizes an answer citing articles by slug, detects corrections inline, and proposes write-backs for novel insights.
platform: both
version: 0.1.0
---

# wiki-ask

**STUB — Phase 4 deliverable.** Not yet functional.

## Intended behavior

### Flow

1. `wiki.search(query, scope)` → top 3–5 articles by rank
2. `wiki.read_article` for each hit (full content + links)
3. Optional: follow 1–2 levels of backlinks if the answer spans topics
4. Synthesize answer, cite by slug
5. **Inline correction detection** — if the next user turn negates a claim ("no, it's X", "estás equivocado", "en realidad"), call `wiki.record_correction`
6. **Write-back step** — if synthesis produced non-trivial new connections or claims:
   - Validate 3+ sentence rule
   - Trigram match against existing
   - If passes filters → create/update article with `sources: [{type: 'ask_writeback', confidence: ...}]`
   - If user rejects ("don't archive that") → `wiki.reject_writeback`
7. `wiki.retrieval_log` always — measures hit rate

### Calibration

Start conservative: confirm "archive this?" before write-back. Relax as heuristics prove out.

## Implementation

TBD.
