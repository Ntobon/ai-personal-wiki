-- 002_rpcs.sql
-- All RPCs return jsonb. Naming mirrors content.*.

-- get_user_context(email) ----------------------------------------------------
-- Bootstrap: returns user row + recent ingest stats + article totals.

create or replace function wiki.get_user_context(p_email text)
returns jsonb language plpgsql as $$
declare
  v_user content.users%rowtype;
  v_totals jsonb;
  v_recent jsonb;
begin
  select * into v_user from content.users where email = p_email;
  if v_user.id is null then
    return jsonb_build_object('found', false, 'email', p_email);
  end if;

  select jsonb_build_object(
    'total', count(*),
    'personal', count(*) filter (where scope = 'personal'),
    'molt', count(*) filter (where scope = 'molt'),
    'shared', count(*) filter (where scope = 'shared')
  )
  into v_totals
  from wiki.articles where user_id = v_user.id;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.ingested_at desc), '[]'::jsonb)
  into v_recent
  from (
    select source_type, source_id, source_scope, ingested_at,
           array_length(articles_touched, 1) as touched
    from wiki.sources
    where user_id = v_user.id
    order by ingested_at desc
    limit 10
  ) s;

  return jsonb_build_object(
    'found', true,
    'user', jsonb_build_object(
      'id', v_user.id,
      'email', v_user.email,
      'display_name', v_user.display_name,
      'preferences', v_user.preferences
    ),
    'totals', coalesce(v_totals, jsonb_build_object('total',0,'personal',0,'molt',0,'shared',0)),
    'recent_ingests', v_recent
  );
end
$$;

-- list_index(user_id, scope) -------------------------------------------------
-- Lightweight index: slug + title + summary + tags.

create or replace function wiki.list_index(p_user_id uuid, p_scope text default null)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', slug,
    'title', title,
    'type', type,
    'scope', scope,
    'summary', summary,
    'tags', tags,
    'updated_at', updated_at
  ) order by title), '[]'::jsonb)
  from wiki.articles
  where user_id = p_user_id
    and (p_scope is null or scope = p_scope);
$$;

-- read_article(user_id, slug) ------------------------------------------------
-- Full article + outbound + backlinks. Bumps last_retrieved_at.

create or replace function wiki.read_article(p_user_id uuid, p_slug text)
returns jsonb language plpgsql as $$
declare
  v_article wiki.articles%rowtype;
  v_outbound jsonb;
  v_backlinks jsonb;
begin
  select * into v_article from wiki.articles
   where user_id = p_user_id and slug = p_slug;
  if v_article.id is null then
    return jsonb_build_object('found', false, 'slug', p_slug);
  end if;

  update wiki.articles set last_retrieved_at = now() where id = v_article.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', a.slug, 'title', a.title, 'context', l.context
  ) order by a.title), '[]'::jsonb)
  into v_outbound
  from wiki.links l join wiki.articles a on a.id = l.to_article
  where l.from_article = v_article.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', a.slug, 'title', a.title, 'context', l.context
  ) order by a.title), '[]'::jsonb)
  into v_backlinks
  from wiki.links l join wiki.articles a on a.id = l.from_article
  where l.to_article = v_article.id;

  return jsonb_build_object(
    'found', true,
    'article', jsonb_build_object(
      'id', v_article.id,
      'slug', v_article.slug,
      'title', v_article.title,
      'type', v_article.type,
      'scope', v_article.scope,
      'content_md', v_article.content_md,
      'summary', v_article.summary,
      'tags', v_article.tags,
      'aliases', v_article.aliases,
      'sources', v_article.sources,
      'manually_edited', v_article.manually_edited,
      'last_manual_edit_at', v_article.last_manual_edit_at,
      'last_retrieved_at', now(),
      'created_at', v_article.created_at,
      'updated_at', v_article.updated_at
    ),
    'outbound', v_outbound,
    'backlinks', v_backlinks
  );
end
$$;

-- search(user_id, query, scope, limit) ---------------------------------------
-- FTS primary + trigram fallback when FTS gives <3 hits. Logs every call.

create or replace function wiki.search(
  p_user_id uuid,
  p_query text,
  p_scope text default null,
  p_limit int default 10
)
returns jsonb language plpgsql as $$
declare
  v_tsq tsquery;
  v_results jsonb;
  v_ids uuid[];
begin
  v_tsq := websearch_to_tsquery('spanish', coalesce(p_query, ''));

  with fts as (
    select a.*,
           ts_rank(a.search_vector, v_tsq) as rank,
           'fts'::text as match_kind
    from wiki.articles a
    where a.user_id = p_user_id
      and (p_scope is null or a.scope = p_scope)
      and a.search_vector @@ v_tsq
    order by rank desc
    limit p_limit
  ),
  trgm as (
    select a.*,
           greatest(similarity(a.title, p_query), similarity(a.content_md, p_query)) as rank,
           'trigram'::text as match_kind
    from wiki.articles a
    where a.user_id = p_user_id
      and (p_scope is null or a.scope = p_scope)
      and (a.title % p_query or a.content_md % p_query)
      and not exists (select 1 from fts f where f.id = a.id)
    order by rank desc
    limit p_limit
  ),
  combined as (
    select * from fts
    union all
    select * from trgm
    limit p_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'slug', slug, 'title', title, 'type', type, 'scope', scope,
      'summary', summary, 'tags', tags,
      'rank', rank, 'match_kind', match_kind
    ) order by rank desc), '[]'::jsonb),
    coalesce(array_agg(id), '{}'::uuid[])
  into v_results, v_ids
  from combined;

  insert into wiki.retrieval_log (user_id, query, scope_filter, results_count, articles_returned)
  values (p_user_id, p_query, p_scope, coalesce(array_length(v_ids,1),0), v_ids);

  return v_results;
end
$$;

-- find_by_alias(user_id, name, type?) ----------------------------------------
-- Dedup lookup: exact slug, title, alias, then fuzzy trigram.

create or replace function wiki.find_by_alias(
  p_user_id uuid,
  p_name text,
  p_type text default null
)
returns jsonb language plpgsql as $$
declare
  v_norm text := lower(trim(p_name));
  v_hit wiki.articles%rowtype;
  v_fuzzy jsonb;
begin
  select * into v_hit from wiki.articles
   where user_id = p_user_id
     and (p_type is null or type = p_type)
     and (slug = v_norm
          or lower(title) = v_norm
          or v_norm = any (select lower(x) from unnest(aliases) x))
   limit 1;

  if v_hit.id is not null then
    return jsonb_build_object(
      'match', 'exact',
      'article', jsonb_build_object(
        'id', v_hit.id, 'slug', v_hit.slug, 'title', v_hit.title,
        'type', v_hit.type, 'scope', v_hit.scope
      )
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'slug', slug, 'title', title, 'type', type, 'scope', scope,
    'similarity', sim
  ) order by sim desc), '[]'::jsonb)
  into v_fuzzy
  from (
    select a.id, a.slug, a.title, a.type, a.scope,
           greatest(similarity(a.title, p_name),
                    coalesce((select max(similarity(x, p_name)) from unnest(a.aliases) x), 0)) as sim
    from wiki.articles a
    where a.user_id = p_user_id
      and (p_type is null or a.type = p_type)
      and (a.title % p_name or a.aliases && array[p_name])
    order by sim desc
    limit 5
  ) q;

  return jsonb_build_object(
    'match', case when (v_fuzzy = '[]'::jsonb) then 'none' else 'fuzzy' end,
    'candidates', v_fuzzy
  );
end
$$;

-- upsert_article(payload) ----------------------------------------------------
-- Create or update. Preserves manually_edited=true unless force=true.
-- Payload keys: user_id, slug, title, type, scope, content_md, summary,
--               tags, aliases, sources, manually_edited, force.

create or replace function wiki.upsert_article(p jsonb)
returns jsonb language plpgsql as $$
declare
  v_user_id uuid := (p->>'user_id')::uuid;
  v_slug text := p->>'slug';
  v_existing wiki.articles%rowtype;
  v_force boolean := coalesce((p->>'force')::boolean, false);
  v_manual boolean := coalesce((p->>'manually_edited')::boolean, false);
  v_now timestamptz := now();
  v_id uuid;
  v_action text;
begin
  if v_user_id is null or v_slug is null then
    raise exception 'user_id and slug are required';
  end if;

  select * into v_existing from wiki.articles
   where user_id = v_user_id and slug = v_slug;

  if v_existing.id is null then
    insert into wiki.articles (
      user_id, slug, title, type, scope, content_md, summary,
      tags, aliases, sources, manually_edited, last_manual_edit_at
    ) values (
      v_user_id,
      v_slug,
      coalesce(p->>'title', v_slug),
      coalesce(p->>'type', 'concept'),
      coalesce(p->>'scope', 'shared'),
      coalesce(p->>'content_md', ''),
      coalesce(p->>'summary', ''),
      coalesce(array(select jsonb_array_elements_text(p->'tags')), '{}'),
      coalesce(array(select jsonb_array_elements_text(p->'aliases')), '{}'),
      coalesce(p->'sources', '[]'::jsonb),
      v_manual,
      case when v_manual then v_now else null end
    )
    returning id into v_id;
    v_action := 'created';
  else
    if v_existing.manually_edited and not v_force then
      return jsonb_build_object(
        'action', 'skipped',
        'reason', 'manually_edited',
        'id', v_existing.id,
        'slug', v_existing.slug
      );
    end if;

    update wiki.articles set
      title       = coalesce(p->>'title', title),
      type        = coalesce(p->>'type', type),
      scope       = coalesce(p->>'scope', scope),
      content_md  = coalesce(p->>'content_md', content_md),
      summary     = coalesce(p->>'summary', summary),
      tags        = coalesce(
                      case when p ? 'tags'
                           then array(select jsonb_array_elements_text(p->'tags'))
                      end,
                      tags),
      aliases     = coalesce(
                      case when p ? 'aliases'
                           then array(select jsonb_array_elements_text(p->'aliases'))
                      end,
                      aliases),
      sources     = coalesce(p->'sources', sources),
      manually_edited = case when v_manual then true else manually_edited end,
      last_manual_edit_at = case when v_manual then v_now else last_manual_edit_at end
    where id = v_existing.id
    returning id into v_id;
    v_action := 'updated';
  end if;

  return jsonb_build_object(
    'action', v_action,
    'id', v_id,
    'slug', v_slug
  );
end
$$;

-- rebuild_links(article_id) --------------------------------------------------
-- Scan content_md for [[slug]] and [[slug|label]] patterns; refresh wiki.links.

create or replace function wiki.rebuild_links(p_article_id uuid)
returns jsonb language plpgsql as $$
declare
  v_article wiki.articles%rowtype;
  v_slugs text[];
  v_inserted int := 0;
  v_missing text[] := '{}';
begin
  select * into v_article from wiki.articles where id = p_article_id;
  if v_article.id is null then
    return jsonb_build_object('found', false);
  end if;

  with matches as (
    select distinct
      split_part(trim(both from m[1]), '|', 1) as raw
    from regexp_matches(v_article.content_md, '\[\[([^\]]+)\]\]', 'g') as m
  )
  select array_agg(lower(trim(raw))) into v_slugs from matches where raw <> '';

  delete from wiki.links where from_article = p_article_id;

  if v_slugs is null then
    return jsonb_build_object('found', true, 'links', 0, 'missing', '[]'::jsonb);
  end if;

  with target as (
    select unnest(v_slugs) as slug
  ),
  resolved as (
    insert into wiki.links (from_article, to_article, context)
    select p_article_id, a.id, null
    from target t
    join wiki.articles a
      on a.user_id = v_article.user_id
     and a.slug = t.slug
    on conflict (from_article, to_article) do nothing
    returning to_article
  )
  select count(*) into v_inserted from resolved;

  select array_agg(t.slug)
  into v_missing
  from unnest(v_slugs) as t(slug)
  where not exists (
    select 1 from wiki.articles a
    where a.user_id = v_article.user_id and a.slug = t.slug
  );

  return jsonb_build_object(
    'found', true,
    'links', v_inserted,
    'missing', coalesce(to_jsonb(v_missing), '[]'::jsonb)
  );
end
$$;

-- log_source(payload) --------------------------------------------------------
-- Record an ingest. Idempotent on (user_id, source_type, source_id).
-- Payload: user_id, source_type, source_id, source_scope, articles_touched[].

create or replace function wiki.log_source(p jsonb)
returns jsonb language plpgsql as $$
declare
  v_id uuid;
  v_action text;
  v_touched uuid[] := coalesce(
    array(select (x)::uuid from jsonb_array_elements_text(p->'articles_touched') x),
    '{}'
  );
begin
  insert into wiki.sources (user_id, source_type, source_id, source_scope, articles_touched)
  values (
    (p->>'user_id')::uuid,
    p->>'source_type',
    p->>'source_id',
    p->>'source_scope',
    v_touched
  )
  on conflict (user_id, source_type, source_id) do update
    set articles_touched = excluded.articles_touched,
        ingested_at = now()
  returning id into v_id;

  v_action := case when (select count(*) from wiki.sources
                         where id = v_id and ingested_at > now() - interval '1 second') > 0
                   then 'recorded' else 'updated' end;
  return jsonb_build_object('id', v_id, 'action', v_action);
end
$$;

-- recent_ingests(user_id, limit) ---------------------------------------------

create or replace function wiki.recent_ingests(p_user_id uuid, p_limit int default 20)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(to_jsonb(s) order by s.ingested_at desc), '[]'::jsonb)
  from (
    select source_type, source_id, source_scope, ingested_at, articles_touched
    from wiki.sources
    where user_id = p_user_id
    order by ingested_at desc
    limit p_limit
  ) s;
$$;

-- orphans(user_id) -----------------------------------------------------------
-- Articles with no inbound and no outbound links.

create or replace function wiki.orphans(p_user_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'slug', a.slug, 'title', a.title, 'type', a.type
  ) order by a.title), '[]'::jsonb)
  from wiki.articles a
  where a.user_id = p_user_id
    and not exists (select 1 from wiki.links l where l.from_article = a.id)
    and not exists (select 1 from wiki.links l where l.to_article = a.id);
$$;

-- record_correction(payload) -------------------------------------------------
-- Payload: user_id, article_id, original_claim, corrected_claim, reason,
--          detected_in, apply_to_article (boolean).

create or replace function wiki.record_correction(p jsonb)
returns jsonb language plpgsql as $$
declare
  v_id uuid;
  v_apply boolean := coalesce((p->>'apply_to_article')::boolean, false);
  v_article_id uuid := nullif(p->>'article_id', '')::uuid;
  v_updated boolean := false;
begin
  insert into wiki.corrections (
    user_id, article_id, original_claim, corrected_claim, reason, detected_in
  ) values (
    (p->>'user_id')::uuid,
    v_article_id,
    p->>'original_claim',
    p->>'corrected_claim',
    p->>'reason',
    coalesce(p->>'detected_in', 'manual')
  )
  returning id into v_id;

  if v_apply and v_article_id is not null then
    update wiki.articles
       set content_md = replace(content_md, p->>'original_claim', p->>'corrected_claim')
     where id = v_article_id
       and content_md like '%' || (p->>'original_claim') || '%';
    get diagnostics v_updated = ROW_COUNT;
  end if;

  return jsonb_build_object('id', v_id, 'article_updated', v_updated);
end
$$;

-- reject_writeback(payload) --------------------------------------------------
-- Payload: user_id, proposed_content, rejection_reason.

create or replace function wiki.reject_writeback(p jsonb)
returns jsonb language plpgsql as $$
declare
  v_id uuid;
begin
  insert into wiki.rejected_writebacks (user_id, proposed_content, rejection_reason)
  values (
    (p->>'user_id')::uuid,
    p->>'proposed_content',
    p->>'rejection_reason'
  )
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end
$$;

-- lint_summary(user_id) ------------------------------------------------------
-- Latest lint run + health metrics.

create or replace function wiki.lint_summary(p_user_id uuid)
returns jsonb language plpgsql as $$
declare
  v_last jsonb;
  v_metrics jsonb;
begin
  select to_jsonb(r) into v_last
  from (
    select id, started_at, finished_at, findings, fixes_applied
    from wiki.lint_runs
    where user_id = p_user_id
    order by started_at desc
    limit 1
  ) r;

  select jsonb_build_object(
    'articles_total', count(*) filter (where a.id is not null),
    'orphans', (
      select count(*) from wiki.articles a2
      where a2.user_id = p_user_id
        and not exists (select 1 from wiki.links l where l.from_article = a2.id)
        and not exists (select 1 from wiki.links l where l.to_article = a2.id)
    ),
    'never_retrieved', count(*) filter (where a.id is not null and a.last_retrieved_at is null),
    'stale_90d', count(*) filter (
      where a.id is not null and (a.last_retrieved_at is null or a.last_retrieved_at < now() - interval '90 days')
    ),
    'corrections_30d', (
      select count(*) from wiki.corrections c
      where c.user_id = p_user_id and c.corrected_at > now() - interval '30 days'
    ),
    'rejected_30d', (
      select count(*) from wiki.rejected_writebacks r
      where r.user_id = p_user_id and r.rejected_at > now() - interval '30 days'
    )
  )
  into v_metrics
  from wiki.articles a
  where a.user_id = p_user_id;

  return jsonb_build_object(
    'last_run', coalesce(v_last, 'null'::jsonb),
    'metrics', v_metrics
  );
end
$$;
