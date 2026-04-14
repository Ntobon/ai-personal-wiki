---
name: wiki-ask
description: Query the personal wiki with write-back and correction detection. Use this skill when the user asks questions that should be grounded in previously ingested knowledge — "what do we know about X", "ask the wiki", "qué sabemos de Y", "consulta el wiki sobre Z". Synthesizes answers citing article slugs, detects corrections in follow-ups, and proposes conservative write-backs for novel insights.
platform: both
version: 0.2.0
---

# wiki-ask

Query the wiki, synthesize grounded answers, and optionally write new insights back as articles or sections.

## Bootstrap

1. Resolve `supabase_project_id` (`wjypineoplzwayvktorc`) and `user_email` (config → memory → ask).
2. `select wiki.get_user_context('<email>')` — cache `user_id`, check if the wiki has any articles before searching.
3. Transport: personal/mobile → Supabase MCP; MOLT → `mcp__wiki-proxy__*` (if missing, bail with a clear message).

## Query flow

### 1. Search

`wiki.search(user_id, query_text, scope, 5)`. If the user specified a scope ("about molt work", "personal projects"), pass it; otherwise leave null. The RPC logs every call to `wiki.retrieval_log` automatically.

- Zero results → tell the user the wiki has no hit, offer two options: (a) answer from your general knowledge with the explicit caveat that nothing in the wiki supports it, or (b) run `/wiki-ingest` to see if new sources might cover it.
- 1+ results → continue.

### 2. Read the top hits

For each of the top 3 hits with rank > 0.05 (FTS) or similarity > 0.3 (trigram), call `wiki.read_article(user_id, slug)`. Collect:

- `article.content_md` — the full content
- `outbound` and `backlinks` — for follow-ups

If the answer genuinely spans topics, follow one level of the most relevant backlink or outbound link — but never more than 2 extra reads per question. Budget: five `read_article` calls max for any single question.

### 3. Synthesize

Write the answer in Wikipedia tone: short sentences, attribution over assertion, no AI hedging. Cite every claim with the source slug in brackets: `(see [[slug]])` or a footer list.

- **Be explicit about uncertainty.** If two articles disagree, say so. If the wiki is thin on this topic, say the answer is best-effort.
- **Do not invent.** Every specific claim must trace to an article you read in step 2. If the user needs knowledge not in the wiki, say so before offering general-knowledge fill-in.
- **Answer length matches the question.** A one-line question gets one paragraph, not three.

## Correction detection

Watch the next user turn after answering. If they negate any of your claims — "no, it's X", "actually, it's Y", "estás equivocado", "en realidad era...", "that's wrong" — treat it as a correction.

Call `wiki.record_correction`:

```json
{
  "user_id": "...",
  "article_id": "<article_id from the read in step 2>",
  "original_claim": "<quote the exact sentence you wrote>",
  "corrected_claim": "<what the user said is true>",
  "reason": "<short — their one-line reason, if any>",
  "detected_in": "wiki-ask",
  "apply_to_article": true
}
```

`apply_to_article: true` makes the RPC rewrite the matching substring in the article's `content_md`. Only set it true when the original claim is a single self-contained sentence present in exactly one article. For multi-sentence corrections or ambiguous matches, set it false and tell the user the correction was logged but the article needs manual editing.

After recording, acknowledge in one sentence: "Logged — updated [[slug]]."

## Write-back

If the synthesis produced genuinely new connections or claims not present in any article you read, consider a write-back. Be conservative — more wiki is not automatically better.

### When to propose a write-back

- The answer required synthesizing 2+ articles into a new statement that neither article alone supported.
- The user said something factual in the conversation that deserves capture as a claim on an article.
- A named entity came up that has no article yet and passes the 3+ substantive sentences rule.

### When NOT to propose

- The answer was a straightforward quote from one article.
- The new claim is speculative, trend-based, or subjective.
- The user is venting, brainstorming, or exploring — not asserting facts.

### How to propose

Ask once: "Want me to archive this as a new section on [[slug]] / a new article `<proposed-slug>`? (y/n)"

- `y` → call `wiki.upsert_article` (with `sources: [{type: 'ask_writeback', question: '...', confidence: 'medium'}]`), then `wiki.rebuild_links` on the article. Confirm one line: "Archived."
- `n` or decline → call `wiki.reject_writeback` with `proposed_content` (what you would have written) and `rejection_reason` (user's one-liner or "declined without reason").
- Silence / user changes topic → do nothing, don't push.

### Start conservative

At MVP, the default is **ask before archiving**. Once heuristics prove out over weeks of use, you can shift to automatic archiving for high-confidence cases. Do not shift unilaterally — wait for explicit user approval to relax.

## Follow-ups

Multiple turns on the same topic are one "ask" session. Reuse cached `read_article` results — do not re-fetch within a session unless the user asks for fresh data.

If the user asks "show me related" or "what else is there?", show `list_index` filtered by tag or scope; do not re-synthesize.

## Error behavior

- RPC timeout/error → surface the error, don't silently fall back to general knowledge.
- `read_article` returns `found: false` on a slug returned by `search` → that's a bug; log it and skip.

## Non-goals

- Not a contradiction detector (that's `wiki-lint`).
- Not a lint runner (that's `/wiki-lint`).
- Not an ingest (that's `/wiki-ingest`).
