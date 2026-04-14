-- 000_local_content_stub.sql
-- Idempotent stub for the `content.users` table the wiki FKs into.
-- In the production Supabase project (wjypineoplzwayvktorc) this schema already
-- exists (owned by content-queue). Locally we need a minimal stand-in so the
-- wiki.articles.user_id FK resolves. The CREATE ... IF NOT EXISTS guards make
-- this safe to run against prod as a no-op.

create schema if not exists content;

create table if not exists content.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  display_name text,
  is_admin boolean default false,
  preferences jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);
