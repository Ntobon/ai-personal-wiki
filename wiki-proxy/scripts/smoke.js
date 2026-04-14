#!/usr/bin/env node
// Spawn the proxy, speak MCP stdio, verify list_tools + call_tool against prod.
// Requires WIKI_PROXY_SUPABASE_URL + WIKI_PROXY_SUPABASE_KEY in env.

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const entry = resolve(__dirname, "..", "dist", "index.js");

if (!process.env.WIKI_PROXY_SUPABASE_URL || !process.env.WIKI_PROXY_SUPABASE_KEY) {
  console.error("smoke: set WIKI_PROXY_SUPABASE_URL and WIKI_PROXY_SUPABASE_KEY");
  process.exit(2);
}

const email = process.env.WIKI_PROXY_USER_EMAIL;
if (!email) {
  console.error("smoke: set WIKI_PROXY_USER_EMAIL");
  process.exit(2);
}

const proc = spawn("node", [entry], { stdio: ["pipe", "pipe", "inherit"], env: process.env });

let buf = "";
const pending = new Map();

proc.stdout.on("data", (chunk) => {
  buf += chunk.toString("utf8");
  let idx;
  while ((idx = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.id != null && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    } catch {
      // ignore non-JSON (shouldn't happen)
    }
  }
});

let nextId = 1;
function rpc(method, params) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, (msg) => {
      if (msg.error) reject(new Error(msg.error.message ?? "rpc error"));
      else resolve(msg.result);
    });
    proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

function notify(method, params) {
  proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
}

function assert(cond, msg) {
  if (!cond) {
    console.error(`FAIL: ${msg}`);
    proc.kill();
    process.exit(1);
  }
  console.log(`  PASS: ${msg}`);
}

async function main() {
  const init = await rpc("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "smoke", version: "0.0.0" },
  });
  assert(init && init.serverInfo && init.serverInfo.name === "wiki-proxy", "initialize returns serverInfo.name=wiki-proxy");

  notify("notifications/initialized", {});

  const list = await rpc("tools/list", {});
  assert(Array.isArray(list.tools), "tools/list returns tools array");
  assert(list.tools.length === 13, `expected 13 tools, got ${list.tools.length}`);

  const names = list.tools.map((t) => t.name).sort();
  const expected = [
    "wiki_find_by_alias",
    "wiki_get_user_context",
    "wiki_lint_summary",
    "wiki_list_index",
    "wiki_log_source",
    "wiki_orphans",
    "wiki_read_article",
    "wiki_rebuild_links",
    "wiki_recent_ingests",
    "wiki_record_correction",
    "wiki_reject_writeback",
    "wiki_search",
    "wiki_upsert_article",
  ].sort();
  assert(JSON.stringify(names) === JSON.stringify(expected), "tool names match the 13 RPCs");

  const ctxCall = await rpc("tools/call", {
    name: "wiki_get_user_context",
    arguments: { email },
  });
  const ctx = JSON.parse(ctxCall.content[0].text);
  assert(ctx.found === true, `get_user_context found=true for ${email}`);
  const userId = ctx.user.id;

  const idxCall = await rpc("tools/call", {
    name: "wiki_list_index",
    arguments: { user_id: userId },
  });
  const idx = JSON.parse(idxCall.content[0].text);
  assert(Array.isArray(idx), "list_index returns array");
  assert(idx.length >= 6, `expected ≥6 articles, got ${idx.length}`);

  const searchCall = await rpc("tools/call", {
    name: "wiki_search",
    arguments: { user_id: userId, query: "agents", limit: 5 },
  });
  const hits = JSON.parse(searchCall.content[0].text);
  assert(Array.isArray(hits) && hits.length > 0, "search returns non-empty array");

  console.log("\nAll smoke checks passed.");
  proc.kill();
  process.exit(0);
}

main().catch((err) => {
  console.error("smoke failed:", err);
  proc.kill();
  process.exit(1);
});
