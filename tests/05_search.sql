-- 05_search.sql — FTS + trigram fallback + retrieval_log side effect.

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'postgres-fts',
  'title', 'Postgres Full Text Search',
  'type', 'concept', 'scope', 'shared',
  'content_md', 'Usamos tsvector, websearch_to_tsquery, y pg_trgm como fallback.',
  'summary', 'FTS en Postgres'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'supabase-setup',
  'title', 'Supabase Setup',
  'type', 'tool', 'scope', 'shared',
  'content_md', 'Proyecto Supabase wjypineoplzwayvktorc.',
  'summary', 'Setup'));

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_res jsonb;
  v_log int;
BEGIN
  -- FTS hit
  v_res := wiki.search(v_user, 'tsvector', NULL, 5);
  ASSERT jsonb_array_length(v_res) >= 1, format('expected fts hit, got %s', v_res);
  ASSERT v_res->0->>'slug' = 'postgres-fts', 'wrong top hit';
  ASSERT v_res->0->>'match_kind' = 'fts', 'should be fts match';

  -- scope filter
  v_res := wiki.search(v_user, 'tsvector', 'personal', 5);
  ASSERT jsonb_array_length(v_res) = 0, 'scope filter should exclude shared';

  -- trigram fallback: similar but not in tsvector dict (typo)
  v_res := wiki.search(v_user, 'Postgrs Full Text', NULL, 5);
  ASSERT jsonb_array_length(v_res) >= 1, format('expected trigram hit, got %s', v_res);

  -- retrieval_log writes
  SELECT count(*) INTO v_log FROM wiki.retrieval_log WHERE user_id = v_user;
  ASSERT v_log = 3, format('expected 3 log rows, got %s', v_log);

  -- empty result still logs
  v_res := wiki.search(v_user, 'xyzzy-no-match', NULL, 5);
  ASSERT v_res = '[]'::jsonb, 'should return empty array on no hits';

  SELECT count(*) INTO v_log FROM wiki.retrieval_log WHERE user_id = v_user;
  ASSERT v_log = 4, 'empty search should still be logged';
END$$;

ROLLBACK;
