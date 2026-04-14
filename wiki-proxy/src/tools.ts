import { callRpc, type WikiClient } from "./supabase.js";

export interface ToolDef {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  run: (client: WikiClient, args: Record<string, unknown>) => Promise<unknown>;
}

const stringProp = (description: string) => ({ type: "string", description });
const uuidProp = (description: string) => ({ type: "string", format: "uuid", description });

export const TOOLS: ToolDef[] = [
  {
    name: "wiki_get_user_context",
    description: "Bootstrap: resolve user + article totals + recent ingests by email.",
    inputSchema: {
      type: "object",
      required: ["email"],
      properties: { email: stringProp("User email (content.users.email)") },
    },
    run: (c, a) => callRpc(c, "get_user_context", { p_email: a.email as string }),
  },
  {
    name: "wiki_list_index",
    description: "Lightweight article index: slug, title, type, scope, summary, tags.",
    inputSchema: {
      type: "object",
      required: ["user_id"],
      properties: {
        user_id: uuidProp("wiki user_id from get_user_context"),
        scope: { type: "string", enum: ["personal", "molt", "shared"], description: "Optional scope filter" },
      },
    },
    run: (c, a) =>
      callRpc(c, "list_index", { p_user_id: a.user_id, p_scope: (a.scope ?? null) as string | null }),
  },
  {
    name: "wiki_read_article",
    description: "Full article + outbound links + backlinks. Bumps last_retrieved_at.",
    inputSchema: {
      type: "object",
      required: ["user_id", "slug"],
      properties: { user_id: uuidProp("user_id"), slug: stringProp("Article slug") },
    },
    run: (c, a) => callRpc(c, "read_article", { p_user_id: a.user_id, p_slug: a.slug }),
  },
  {
    name: "wiki_search",
    description: "FTS + trigram fallback over articles. Auto-logs the query to wiki.retrieval_log.",
    inputSchema: {
      type: "object",
      required: ["user_id", "query"],
      properties: {
        user_id: uuidProp("user_id"),
        query: stringProp("Free-text search"),
        scope: { type: "string", enum: ["personal", "molt", "shared"], description: "Optional scope filter" },
        limit: { type: "integer", minimum: 1, maximum: 50, default: 10 },
      },
    },
    run: (c, a) =>
      callRpc(c, "search", {
        p_user_id: a.user_id,
        p_query: a.query,
        p_scope: (a.scope ?? null) as string | null,
        p_limit: (a.limit ?? 10) as number,
      }),
  },
  {
    name: "wiki_find_by_alias",
    description: "Dedup lookup: exact match (slug/title/alias) or trigram fuzzy candidates.",
    inputSchema: {
      type: "object",
      required: ["user_id", "name"],
      properties: {
        user_id: uuidProp("user_id"),
        name: stringProp("Entity name"),
        type: { type: "string", enum: ["person", "project", "concept", "decision", "tool"] },
      },
    },
    run: (c, a) =>
      callRpc(c, "find_by_alias", {
        p_user_id: a.user_id,
        p_name: a.name,
        p_type: (a.type ?? null) as string | null,
      }),
  },
  {
    name: "wiki_upsert_article",
    description:
      "Create or update an article. Preserves manually_edited=true unless force=true. Payload mirrors wiki.upsert_article.",
    inputSchema: {
      type: "object",
      required: ["user_id", "slug"],
      properties: {
        user_id: uuidProp("user_id"),
        slug: stringProp("Article slug"),
        title: { type: "string" },
        type: { type: "string", enum: ["person", "project", "concept", "decision", "tool"] },
        scope: { type: "string", enum: ["personal", "molt", "shared"] },
        content_md: { type: "string" },
        summary: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        aliases: { type: "array", items: { type: "string" } },
        sources: { type: "array", items: { type: "object" } },
        manually_edited: { type: "boolean" },
        force: { type: "boolean" },
      },
    },
    run: (c, a) => callRpc(c, "upsert_article", { p: a }),
  },
  {
    name: "wiki_rebuild_links",
    description: "Scan [[wikilinks]] in an article's content_md and refresh wiki.links.",
    inputSchema: {
      type: "object",
      required: ["article_id"],
      properties: { article_id: uuidProp("Article id") },
    },
    run: (c, a) => callRpc(c, "rebuild_links", { p_article_id: a.article_id }),
  },
  {
    name: "wiki_log_source",
    description: "Record an ingest. Idempotent on (user_id, source_type, source_id).",
    inputSchema: {
      type: "object",
      required: ["user_id", "source_type", "source_id"],
      properties: {
        user_id: uuidProp("user_id"),
        source_type: {
          type: "string",
          enum: [
            "queue_item",
            "digest",
            "action_item",
            "claude_log_personal",
            "claude_log_molt",
            "repo",
            "notion_skill",
            "manual",
            "ask_writeback",
          ],
        },
        source_id: stringProp("Upstream source id (stringified)"),
        source_scope: { type: "string", enum: ["personal", "molt", "shared"] },
        articles_touched: { type: "array", items: { type: "string", format: "uuid" } },
      },
    },
    run: (c, a) => callRpc(c, "log_source", { p: a }),
  },
  {
    name: "wiki_recent_ingests",
    description: "Chronological list of recent wiki.sources rows for a user.",
    inputSchema: {
      type: "object",
      required: ["user_id"],
      properties: {
        user_id: uuidProp("user_id"),
        limit: { type: "integer", minimum: 1, maximum: 100, default: 20 },
      },
    },
    run: (c, a) =>
      callRpc(c, "recent_ingests", { p_user_id: a.user_id, p_limit: (a.limit ?? 20) as number }),
  },
  {
    name: "wiki_orphans",
    description: "Articles with no inbound or outbound wikilinks.",
    inputSchema: {
      type: "object",
      required: ["user_id"],
      properties: { user_id: uuidProp("user_id") },
    },
    run: (c, a) => callRpc(c, "orphans", { p_user_id: a.user_id }),
  },
  {
    name: "wiki_record_correction",
    description:
      "Log a correction from the user. Set apply_to_article=true to also rewrite the matching substring in content_md.",
    inputSchema: {
      type: "object",
      required: ["user_id", "original_claim", "corrected_claim"],
      properties: {
        user_id: uuidProp("user_id"),
        article_id: uuidProp("Article id (optional if not tied to one)"),
        original_claim: stringProp("The sentence that was wrong"),
        corrected_claim: stringProp("The correct version"),
        reason: { type: "string" },
        detected_in: { type: "string", enum: ["wiki-ask", "manual"] },
        apply_to_article: { type: "boolean" },
      },
    },
    run: (c, a) => callRpc(c, "record_correction", { p: a }),
  },
  {
    name: "wiki_reject_writeback",
    description: "Record a proposed write-back the user rejected; informs future calibration.",
    inputSchema: {
      type: "object",
      required: ["user_id", "proposed_content"],
      properties: {
        user_id: uuidProp("user_id"),
        proposed_content: stringProp("What you were about to archive"),
        rejection_reason: { type: "string" },
      },
    },
    run: (c, a) => callRpc(c, "reject_writeback", { p: a }),
  },
  {
    name: "wiki_lint_summary",
    description: "Latest lint_runs row + health metrics (orphans, stale, corrections, rejected).",
    inputSchema: {
      type: "object",
      required: ["user_id"],
      properties: { user_id: uuidProp("user_id") },
    },
    run: (c, a) => callRpc(c, "lint_summary", { p_user_id: a.user_id }),
  },
];
