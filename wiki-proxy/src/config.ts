import { readFileSync } from "node:fs";

export interface ProxyConfig {
  supabase_url: string;
  supabase_key: string;
  user_email?: string;
}

export function loadConfig(): ProxyConfig {
  const path = process.env.WIKI_PROXY_CONFIG;
  if (path) {
    const raw = readFileSync(path, "utf8");
    const parsed = JSON.parse(raw) as Partial<ProxyConfig>;
    const key = parsed.supabase_key ?? (parsed as Record<string, string>).supabase_anon_key;
    if (!parsed.supabase_url || !key) {
      throw new Error(`wiki-proxy: ${path} must set supabase_url and supabase_key`);
    }
    return {
      supabase_url: parsed.supabase_url,
      supabase_key: key,
      user_email: parsed.user_email,
    };
  }

  const url = process.env.WIKI_PROXY_SUPABASE_URL;
  const key = process.env.WIKI_PROXY_SUPABASE_KEY;
  if (!url || !key) {
    throw new Error(
      "wiki-proxy: set WIKI_PROXY_CONFIG (path to JSON) or WIKI_PROXY_SUPABASE_URL + WIKI_PROXY_SUPABASE_KEY."
    );
  }
  return { supabase_url: url, supabase_key: key, user_email: process.env.WIKI_PROXY_USER_EMAIL };
}
