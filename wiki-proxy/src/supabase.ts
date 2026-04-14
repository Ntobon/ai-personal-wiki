import { createClient } from "@supabase/supabase-js";
import type { ProxyConfig } from "./config.js";

export type WikiClient = ReturnType<typeof makeClient>;

export function makeClient(cfg: ProxyConfig) {
  return createClient(cfg.supabase_url, cfg.supabase_key, {
    auth: { persistSession: false },
  });
}

// PostgREST only exposes schemas listed in the project's `db-schemas` config
// (default: public). The wiki.* RPCs are reached via thin public wrappers named
// public.wiki_<fn>; see migrations/003_public_wrappers.sql.
export async function callRpc(
  client: WikiClient,
  fn: string,
  args: Record<string, unknown>
): Promise<unknown> {
  const { data, error } = await client.rpc(`wiki_${fn}` as never, args as never);
  if (error) {
    throw new Error(`wiki.${fn} failed: ${error.message}`);
  }
  return data;
}
