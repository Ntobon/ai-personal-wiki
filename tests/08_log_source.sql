-- 08_log_source.sql — idempotency is the point.

BEGIN;

INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test');

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_a uuid;
  v_res jsonb;
  v_count int;
BEGIN
  v_a := (wiki.upsert_article(jsonb_build_object(
    'user_id', v_user, 'slug', 'a', 'title', 'A',
    'type', 'concept', 'scope', 'shared', 'content_md', 'x', 'summary', 's'))->>'id')::uuid;

  v_res := wiki.log_source(jsonb_build_object(
    'user_id', v_user,
    'source_type', 'queue_item',
    'source_id', 'queue-123',
    'source_scope', 'personal',
    'articles_touched', jsonb_build_array(v_a::text)
  ));
  ASSERT v_res ? 'id', 'log_source should return id';

  SELECT count(*) INTO v_count FROM wiki.sources
   WHERE user_id = v_user AND source_type = 'queue_item' AND source_id = 'queue-123';
  ASSERT v_count = 1, format('expected 1 source row, got %s', v_count);

  -- replay (same user + type + id) — should not duplicate
  v_res := wiki.log_source(jsonb_build_object(
    'user_id', v_user,
    'source_type', 'queue_item',
    'source_id', 'queue-123',
    'source_scope', 'personal',
    'articles_touched', jsonb_build_array(v_a::text)
  ));

  SELECT count(*) INTO v_count FROM wiki.sources
   WHERE user_id = v_user AND source_type = 'queue_item' AND source_id = 'queue-123';
  ASSERT v_count = 1, format('replay should be idempotent, got %s rows', v_count);
END$$;

ROLLBACK;
