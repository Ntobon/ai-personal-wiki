-- 04_read_article.sql

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'alpha', 'title', 'Alpha', 'type', 'concept', 'scope', 'personal',
  'content_md', 'Alpha references [[beta]] in passing.', 'summary', 's'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'beta',  'title', 'Beta',  'type', 'concept', 'scope', 'personal',
  'content_md', 'Beta talks about [[alpha]].', 'summary', 's'));

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_a uuid := (SELECT id FROM wiki.articles WHERE user_id = v_user AND slug = 'alpha');
  v_b uuid := (SELECT id FROM wiki.articles WHERE user_id = v_user AND slug = 'beta');
  v_res jsonb;
  v_ret timestamptz;
BEGIN
  PERFORM wiki.rebuild_links(v_a);
  PERFORM wiki.rebuild_links(v_b);

  v_res := wiki.read_article(v_user, 'alpha');
  ASSERT (v_res->>'found')::boolean, 'should find alpha';
  ASSERT v_res->'article'->>'slug' = 'alpha', 'wrong slug';
  ASSERT jsonb_array_length(v_res->'outbound') = 1, 'alpha should have 1 outbound link';
  ASSERT v_res->'outbound'->0->>'slug' = 'beta', 'outbound should be beta';
  ASSERT jsonb_array_length(v_res->'backlinks') = 1, 'alpha should have 1 backlink';
  ASSERT v_res->'backlinks'->0->>'slug' = 'beta', 'backlink should be beta';

  -- last_retrieved_at bumped
  SELECT last_retrieved_at INTO v_ret FROM wiki.articles WHERE id = v_a;
  ASSERT v_ret IS NOT NULL, 'last_retrieved_at not set';
  ASSERT v_ret > now() - interval '5 seconds', 'last_retrieved_at not recent';

  -- missing
  v_res := wiki.read_article(v_user, 'does-not-exist');
  ASSERT NOT (v_res->>'found')::boolean, 'should not find missing slug';
END$$;

ROLLBACK;
