-- 02_upsert_article.sql

BEGIN;

INSERT INTO content.users (id, email, display_name)
VALUES ('00000000-0000-0000-0000-000000000001', 'a@test', 'A');

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_res jsonb;
  v_row wiki.articles%ROWTYPE;
BEGIN
  -- create
  v_res := wiki.upsert_article(jsonb_build_object(
    'user_id', v_user,
    'slug', 'farzapedia',
    'title', 'Farzapedia',
    'type', 'project',
    'scope', 'personal',
    'content_md', 'Una referencia al wiki de Farza.',
    'summary', 'Project by Farza.',
    'tags', jsonb_build_array('wiki','reference'),
    'aliases', jsonb_build_array('farzapedia','farza-wiki')
  ));
  ASSERT v_res->>'action' = 'created', format('expected created, got %s', v_res);

  SELECT * INTO v_row FROM wiki.articles WHERE user_id = v_user AND slug = 'farzapedia';
  ASSERT v_row.title = 'Farzapedia', 'title mismatch';
  ASSERT v_row.tags = ARRAY['wiki','reference'], format('tags mismatch: %s', v_row.tags);
  ASSERT NOT v_row.manually_edited, 'expected manually_edited=false';
  ASSERT v_row.search_vector IS NOT NULL, 'search_vector not populated';

  -- update (same slug)
  v_res := wiki.upsert_article(jsonb_build_object(
    'user_id', v_user,
    'slug', 'farzapedia',
    'summary', 'Updated summary.'
  ));
  ASSERT v_res->>'action' = 'updated', format('expected updated, got %s', v_res);

  SELECT * INTO v_row FROM wiki.articles WHERE user_id = v_user AND slug = 'farzapedia';
  ASSERT v_row.summary = 'Updated summary.', 'summary did not update';
  ASSERT v_row.title = 'Farzapedia', 'unspecified fields should be preserved';

  -- manually_edited=true protects from automatic overwrite
  UPDATE wiki.articles
     SET manually_edited = true, last_manual_edit_at = now()
   WHERE user_id = v_user AND slug = 'farzapedia';

  v_res := wiki.upsert_article(jsonb_build_object(
    'user_id', v_user,
    'slug', 'farzapedia',
    'summary', 'Try to overwrite.'
  ));
  ASSERT v_res->>'action' = 'skipped', format('expected skipped, got %s', v_res);
  ASSERT v_res->>'reason' = 'manually_edited', 'wrong skip reason';

  SELECT * INTO v_row FROM wiki.articles WHERE user_id = v_user AND slug = 'farzapedia';
  ASSERT v_row.summary = 'Updated summary.', 'manually_edited article should not have been overwritten';

  -- force=true bypasses the guard
  v_res := wiki.upsert_article(jsonb_build_object(
    'user_id', v_user,
    'slug', 'farzapedia',
    'summary', 'Forced overwrite.',
    'force', true
  ));
  ASSERT v_res->>'action' = 'updated', format('expected updated with force, got %s', v_res);

  SELECT * INTO v_row FROM wiki.articles WHERE user_id = v_user AND slug = 'farzapedia';
  ASSERT v_row.summary = 'Forced overwrite.', 'force did not apply';
  ASSERT v_row.manually_edited, 'manually_edited should stay true after forced update';
END$$;

ROLLBACK;
