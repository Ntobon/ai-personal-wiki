-- schema.sql — reference copy of the full wiki schema.
-- Source of truth: migrations/000_local_content_stub.sql, 001_initial.sql, 002_rpcs.sql.
-- Apply via `make reset` (local) or Supabase MCP apply_migration (prod).
--
-- This file concatenates the migrations for readers who want the whole schema
-- in one place. Keep it in sync whenever a new migration lands.

\i migrations/000_local_content_stub.sql
\i migrations/001_initial.sql
\i migrations/002_rpcs.sql
