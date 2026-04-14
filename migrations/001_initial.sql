-- 001_initial.sql
-- Wiki schema, tables, indexes, triggers.

create extension if not exists pg_trgm;

create schema if not exists wiki;

-- Immutable wrapper so the tsvector generated column is accepted. The built-in
-- to_tsvector(text,text) is only STABLE (resolves the config name at runtime);
-- wrapping it in an IMMUTABLE sql function with a constant regconfig is the
-- standard workaround.
create or replace function wiki.tsv_build(
  p_title text,
  p_aliases text[],
  p_summary text,
  p_tags text[],
  p_content text
) returns tsvector language sql immutable as $fn$
  select
    setweight(to_tsvector('spanish'::regconfig, coalesce(p_title,'')), 'A') ||
    setweight(to_tsvector('spanish'::regconfig, coalesce(array_to_string(p_aliases,' '),'')), 'A') ||
    setweight(to_tsvector('spanish'::regconfig, coalesce(p_summary,'')), 'B') ||
    setweight(to_tsvector('spanish'::regconfig, coalesce(array_to_string(p_tags,' '),'')), 'C') ||
    setweight(to_tsvector('spanish'::regconfig, coalesce(p_content,'')), 'D')
$fn$;

-- articles -------------------------------------------------------------------

create table if not exists wiki.articles (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  title text not null,
  type text not null check (type in ('person','project','concept','decision','tool')),
  scope text not null check (scope in ('personal','molt','shared')),
  content_md text not null,
  summary text not null,
  tags text[] not null default '{}',
  aliases text[] not null default '{}',
  sources jsonb not null default '[]'::jsonb,
  manually_edited boolean not null default false,
  last_manual_edit_at timestamptz,
  last_retrieved_at timestamptz,
  search_vector tsvector generated always as (
    wiki.tsv_build(title, aliases, summary, tags, content_md)
  ) stored,
  user_id uuid not null references content.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint articles_slug_user_unique unique (user_id, slug)
);

create index if not exists articles_fts     on wiki.articles using gin (search_vector);
create index if not exists articles_tags    on wiki.articles using gin (tags);
create index if not exists articles_trgm    on wiki.articles using gin (content_md gin_trgm_ops);
create index if not exists articles_title_trgm on wiki.articles using gin (title gin_trgm_ops);
create index if not exists articles_scope   on wiki.articles (user_id, scope);
create index if not exists articles_lastret on wiki.articles (user_id, last_retrieved_at);
create index if not exists articles_type    on wiki.articles (user_id, type);

-- links ----------------------------------------------------------------------

create table if not exists wiki.links (
  from_article uuid not null references wiki.articles(id) on delete cascade,
  to_article   uuid not null references wiki.articles(id) on delete cascade,
  context text,
  primary key (from_article, to_article)
);

create index if not exists links_to on wiki.links (to_article);

-- sources --------------------------------------------------------------------

create table if not exists wiki.sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references content.users(id) on delete cascade,
  source_type text not null check (source_type in (
    'queue_item','digest','action_item',
    'claude_log_personal','claude_log_molt',
    'repo','notion_skill','manual','ask_writeback'
  )),
  source_id text not null,
  source_scope text check (source_scope in ('personal','molt','shared')),
  ingested_at timestamptz not null default now(),
  articles_touched uuid[] not null default '{}',
  constraint sources_unique unique (user_id, source_type, source_id)
);

create index if not exists sources_user_time on wiki.sources (user_id, ingested_at desc);

-- corrections ----------------------------------------------------------------

create table if not exists wiki.corrections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references content.users(id) on delete cascade,
  article_id uuid references wiki.articles(id) on delete set null,
  original_claim text not null,
  corrected_claim text not null,
  reason text,
  detected_in text check (detected_in in ('wiki-ask','manual')),
  corrected_at timestamptz not null default now()
);

create index if not exists corrections_user_time on wiki.corrections (user_id, corrected_at desc);
create index if not exists corrections_article on wiki.corrections (article_id);

-- retrieval_log --------------------------------------------------------------

create table if not exists wiki.retrieval_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references content.users(id) on delete cascade,
  query text not null,
  scope_filter text,
  results_count int not null default 0,
  articles_returned uuid[] not null default '{}',
  user_accepted boolean,
  asked_at timestamptz not null default now()
);

create index if not exists retrieval_user_time on wiki.retrieval_log (user_id, asked_at desc);

-- rejected_writebacks --------------------------------------------------------

create table if not exists wiki.rejected_writebacks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references content.users(id) on delete cascade,
  proposed_content text not null,
  rejection_reason text,
  rejected_at timestamptz not null default now()
);

-- lint_runs ------------------------------------------------------------------

create table if not exists wiki.lint_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references content.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  findings jsonb,
  fixes_applied jsonb
);

create index if not exists lint_user_time on wiki.lint_runs (user_id, started_at desc);

-- updated_at trigger ---------------------------------------------------------

create or replace function wiki.tg_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists articles_set_updated_at on wiki.articles;
create trigger articles_set_updated_at
  before update on wiki.articles
  for each row execute function wiki.tg_set_updated_at();
