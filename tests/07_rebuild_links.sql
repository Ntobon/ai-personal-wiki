-- 07_rebuild_links.sql

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'source',
  'title', 'Source',
  'type', 'concept', 'scope', 'shared',
  'content_md', 'Links to [[target-a]] and [[target-b|Label B]]. Also mentions [[missing-slug]].',
  'summary', 's'));

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'target-a', 'title', 'Target A', 'type', 'concept', 'scope', 'shared',
  'content_md', 'x', 'summary', 's'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'target-b', 'title', 'Target B', 'type', 'concept', 'scope', 'shared',
  'content_md', 'x', 'summary', 's'));

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_src uuid := (SELECT id FROM wiki.articles WHERE user_id = v_user AND slug = 'source');
  v_res jsonb;
  v_count int;
BEGIN
  v_res := wiki.rebuild_links(v_src);
  ASSERT (v_res->>'found')::boolean, 'article not found';
  ASSERT (v_res->>'links')::int = 2, format('expected 2 links, got %s', v_res);
  ASSERT v_res->'missing' ? 'missing-slug', format('missing-slug not reported: %s', v_res);

  SELECT count(*) INTO v_count FROM wiki.links WHERE from_article = v_src;
  ASSERT v_count = 2, format('expected 2 rows in links, got %s', v_count);

  -- rerun: idempotent
  v_res := wiki.rebuild_links(v_src);
  SELECT count(*) INTO v_count FROM wiki.links WHERE from_article = v_src;
  ASSERT v_count = 2, format('rerun produced %s rows (should still be 2)', v_count);

  -- missing article
  v_res := wiki.rebuild_links(gen_random_uuid());
  ASSERT NOT (v_res->>'found')::boolean, 'non-existent article should return found=false';
END$$;

ROLLBACK;
