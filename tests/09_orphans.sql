-- 09_orphans.sql

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'linked-a', 'title', 'Linked A', 'type', 'concept', 'scope', 'shared',
  'content_md', 'Refs [[linked-b]].', 'summary', 's'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'linked-b', 'title', 'Linked B', 'type', 'concept', 'scope', 'shared',
  'content_md', 'x', 'summary', 's'));
SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'orphan', 'title', 'Orphan', 'type', 'concept', 'scope', 'shared',
  'content_md', 'No links out, no links in.', 'summary', 's'));

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_a uuid := (SELECT id FROM wiki.articles WHERE slug = 'linked-a' AND user_id = v_user);
  v_res jsonb;
BEGIN
  PERFORM wiki.rebuild_links(v_a);

  v_res := wiki.orphans(v_user);
  ASSERT jsonb_array_length(v_res) = 1, format('expected 1 orphan, got %s: %s',
                                                jsonb_array_length(v_res), v_res);
  ASSERT v_res->0->>'slug' = 'orphan', format('wrong orphan: %s', v_res);
END$$;

ROLLBACK;
