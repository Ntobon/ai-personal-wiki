-- 003_public_wrappers.sql
-- PostgREST only exposes schemas listed in the project's db-schemas config
-- (default: public). Rather than fight that, add thin public wrappers with a
-- wiki_ prefix so Supabase clients can reach them via the default REST surface
-- while the real logic stays in the wiki schema.
--
-- SECURITY DEFINER with a locked search_path: the caller (anon, authenticated)
-- does NOT need USAGE on the wiki schema — the wrapper runs with the owner's
-- privileges. search_path is pinned to (wiki, public, pg_temp) so the wrappers
-- always resolve wiki.* first regardless of the caller's session state.

create or replace function public.wiki_get_user_context(p_email text)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.get_user_context(p_email);
$$;

create or replace function public.wiki_list_index(p_user_id uuid, p_scope text default null)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.list_index(p_user_id, p_scope);
$$;

create or replace function public.wiki_read_article(p_user_id uuid, p_slug text)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.read_article(p_user_id, p_slug);
$$;

create or replace function public.wiki_search(p_user_id uuid, p_query text, p_scope text default null, p_limit int default 10)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.search(p_user_id, p_query, p_scope, p_limit);
$$;

create or replace function public.wiki_find_by_alias(p_user_id uuid, p_name text, p_type text default null)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.find_by_alias(p_user_id, p_name, p_type);
$$;

create or replace function public.wiki_upsert_article(p jsonb)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.upsert_article(p);
$$;

create or replace function public.wiki_rebuild_links(p_article_id uuid)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.rebuild_links(p_article_id);
$$;

create or replace function public.wiki_log_source(p jsonb)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.log_source(p);
$$;

create or replace function public.wiki_recent_ingests(p_user_id uuid, p_limit int default 20)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.recent_ingests(p_user_id, p_limit);
$$;

create or replace function public.wiki_orphans(p_user_id uuid)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.orphans(p_user_id);
$$;

create or replace function public.wiki_record_correction(p jsonb)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.record_correction(p);
$$;

create or replace function public.wiki_reject_writeback(p jsonb)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.reject_writeback(p);
$$;

create or replace function public.wiki_lint_summary(p_user_id uuid)
returns jsonb language sql security definer set search_path = wiki, public, pg_temp as $$
  select wiki.lint_summary(p_user_id);
$$;
