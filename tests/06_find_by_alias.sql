-- 06_find_by_alias.sql

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'alejandro', 'title', 'Alejandro Gómez', 'type', 'person', 'scope', 'personal',
  'content_md', 'x', 'summary', 's',
  'aliases', jsonb_build_array('Alex','alex','Alejo')));

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_res jsonb;
BEGIN
  -- exact by slug
  v_res := wiki.find_by_alias(v_user, 'alejandro');
  ASSERT v_res->>'match' = 'exact', format('expected exact, got %s', v_res);
  ASSERT v_res->'article'->>'slug' = 'alejandro', 'wrong article';

  -- exact by title (case insensitive)
  v_res := wiki.find_by_alias(v_user, 'alejandro gómez');
  ASSERT v_res->>'match' = 'exact', 'case-insensitive title match failed';

  -- exact by alias
  v_res := wiki.find_by_alias(v_user, 'alex');
  ASSERT v_res->>'match' = 'exact', 'alias match failed';

  -- type filter
  v_res := wiki.find_by_alias(v_user, 'alejandro', 'project');
  ASSERT v_res->>'match' = 'none', 'type filter should exclude person';

  -- unknown
  v_res := wiki.find_by_alias(v_user, 'zzz-no-such-name');
  ASSERT v_res->>'match' = 'none', 'should be none';
  ASSERT v_res->'candidates' = '[]'::jsonb, 'no fuzzy candidates expected';
END$$;

ROLLBACK;
