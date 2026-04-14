-- 10_corrections.sql

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

SELECT wiki.upsert_article(jsonb_build_object(
  'user_id', '00000000-0000-0000-0000-000000000001',
  'slug', 'alpha', 'title', 'Alpha', 'type', 'concept', 'scope', 'shared',
  'content_md', 'Alpha was released in 2025.', 'summary', 's'));

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_a uuid := (SELECT id FROM wiki.articles WHERE slug = 'alpha' AND user_id = v_user);
  v_res jsonb;
  v_content text;
  v_count int;
BEGIN
  -- log only (no apply)
  v_res := wiki.record_correction(jsonb_build_object(
    'user_id', v_user,
    'article_id', v_a,
    'original_claim', 'Alpha was released in 2025.',
    'corrected_claim', 'Alpha was released in 2024.',
    'reason', 'user clarified',
    'detected_in', 'wiki-ask'
  ));
  ASSERT v_res ? 'id', 'missing id';
  ASSERT NOT (v_res->>'article_updated')::boolean, 'should not update without apply flag';

  SELECT content_md INTO v_content FROM wiki.articles WHERE id = v_a;
  ASSERT v_content = 'Alpha was released in 2025.', 'article should be untouched';

  -- log + apply
  v_res := wiki.record_correction(jsonb_build_object(
    'user_id', v_user,
    'article_id', v_a,
    'original_claim', 'Alpha was released in 2025.',
    'corrected_claim', 'Alpha was released in 2024.',
    'detected_in', 'manual',
    'apply_to_article', true
  ));
  ASSERT (v_res->>'article_updated')::boolean, 'should have updated the article';

  SELECT content_md INTO v_content FROM wiki.articles WHERE id = v_a;
  ASSERT v_content = 'Alpha was released in 2024.', format('content not replaced: %s', v_content);

  SELECT count(*) INTO v_count FROM wiki.corrections
   WHERE user_id = v_user AND article_id = v_a;
  ASSERT v_count = 2, format('expected 2 correction rows, got %s', v_count);

  -- reject_writeback
  v_res := wiki.reject_writeback(jsonb_build_object(
    'user_id', v_user,
    'proposed_content', 'Some speculative claim.',
    'rejection_reason', 'not substantiated'
  ));
  ASSERT v_res ? 'id', 'reject_writeback missing id';

  SELECT count(*) INTO v_count FROM wiki.rejected_writebacks WHERE user_id = v_user;
  ASSERT v_count = 1, format('expected 1 rejected_writeback, got %s', v_count);
END$$;

ROLLBACK;
