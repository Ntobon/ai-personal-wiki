-- 03_list_index.sql

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test'),
  ('00000000-0000-0000-0000-000000000002', 'b@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'alpha', 'title', 'Alpha', 'type', 'concept', 'scope', 'personal',
  'content_md', 'x', 'summary', 's'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'beta',  'title', 'Beta',  'type', 'concept', 'scope', 'molt',
  'content_md', 'y', 'summary', 's'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000002',
  'slug', 'gamma', 'title', 'Gamma', 'type', 'concept', 'scope', 'personal',
  'content_md', 'z', 'summary', 's'));

DO $$
DECLARE
  v_user_a uuid := '00000000-0000-0000-0000-000000000001';
  v_user_b uuid := '00000000-0000-0000-0000-000000000002';
  v_res jsonb;
BEGIN
  v_res := wiki.list_index(v_user_a, NULL);
  ASSERT jsonb_array_length(v_res) = 2, format('expected 2, got %s: %s', jsonb_array_length(v_res), v_res);

  v_res := wiki.list_index(v_user_a, 'personal');
  ASSERT jsonb_array_length(v_res) = 1, format('expected 1 personal, got %s', jsonb_array_length(v_res));
  ASSERT v_res->0->>'slug' = 'alpha', format('wrong slug: %s', v_res);

  -- sorted by title
  v_res := wiki.list_index(v_user_a, NULL);
  ASSERT v_res->0->>'title' = 'Alpha', 'not sorted by title';
  ASSERT v_res->1->>'title' = 'Beta', 'not sorted by title';

  -- user isolation
  v_res := wiki.list_index(v_user_b, NULL);
  ASSERT jsonb_array_length(v_res) = 1, 'user_b should only see their own';
  ASSERT v_res->0->>'slug' = 'gamma', 'cross-user leak';

  -- empty
  v_res := wiki.list_index(gen_random_uuid(), NULL);
  ASSERT v_res = '[]'::jsonb, 'unknown user should return empty array';
END$$;

ROLLBACK;
