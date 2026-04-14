-- 11_user_context_lint.sql — get_user_context, recent_ingests, lint_summary.

BEGIN;

INSERT INTO content.users (id, email, display_name, preferences) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test', 'User A', '{"scope":"personal"}'::jsonb);

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_res jsonb;
  v_a uuid;
BEGIN
  -- get_user_context: unknown user
  v_res := wiki.get_user_context('no-such@test');
  ASSERT NOT (v_res->>'found')::boolean, 'unknown email should be found=false';

  -- get_user_context: known user, empty wiki
  v_res := wiki.get_user_context('a@test');
  ASSERT (v_res->>'found')::boolean, 'known email should be found=true';
  ASSERT (v_res->'totals'->>'total')::int = 0, 'empty totals';
  ASSERT v_res->'recent_ingests' = '[]'::jsonb, 'empty recent_ingests';

  -- seed one article + one source
  v_a := (wiki.upsert_article(jsonb_build_object(
    'user_id', v_user, 'slug', 'a', 'title', 'A', 'type', 'concept', 'scope', 'personal',
    'content_md', 'x', 'summary', 's'))->>'id')::uuid;

  PERFORM wiki.log_source(jsonb_build_object(
    'user_id', v_user, 'source_type', 'queue_item', 'source_id', 'q1',
    'source_scope', 'personal',
    'articles_touched', jsonb_build_array(v_a::text)));

  v_res := wiki.get_user_context('a@test');
  ASSERT (v_res->'totals'->>'total')::int = 1, 'totals.total should be 1';
  ASSERT (v_res->'totals'->>'personal')::int = 1, 'totals.personal should be 1';
  ASSERT jsonb_array_length(v_res->'recent_ingests') = 1, 'recent_ingests should have 1';

  -- recent_ingests directly
  v_res := wiki.recent_ingests(v_user, 10);
  ASSERT jsonb_array_length(v_res) = 1, 'recent_ingests returned wrong count';

  -- lint_summary on a system with no lint_runs
  v_res := wiki.lint_summary(v_user);
  ASSERT v_res ? 'metrics', 'lint_summary missing metrics';
  ASSERT v_res->'last_run' = 'null'::jsonb, 'last_run should be null';
  ASSERT (v_res->'metrics'->>'articles_total')::int = 1, 'metrics.articles_total wrong';
  ASSERT (v_res->'metrics'->>'never_retrieved')::int = 1, 'metrics.never_retrieved wrong';
  ASSERT (v_res->'metrics'->>'corrections_30d')::int = 0, 'metrics.corrections_30d wrong';

  -- insert a lint_run, re-check
  INSERT INTO wiki.lint_runs (user_id, finished_at, findings, fixes_applied)
  VALUES (v_user, now(), '[{"kind":"orphan","count":0}]'::jsonb, '{}'::jsonb);

  v_res := wiki.lint_summary(v_user);
  ASSERT v_res->'last_run' IS NOT NULL AND v_res->'last_run' <> 'null'::jsonb,
    'last_run should now be populated';
END$$;

ROLLBACK;
