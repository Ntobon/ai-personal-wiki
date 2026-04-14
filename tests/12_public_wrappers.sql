-- 12_public_wrappers.sql — public.wiki_* wrappers exist, are DEFINER, and
-- delegate to wiki.*.

DO $$
DECLARE
  v_count int;
  v_security text;
BEGIN
  SELECT count(*) INTO v_count FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'wiki_%' AND p.prokind = 'f';
  ASSERT v_count = 13, format('expected 13 public.wiki_* wrappers, got %s', v_count);

  SELECT count(*) INTO v_count FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'wiki_%' AND NOT p.prosecdef;
  ASSERT v_count = 0, format('expected all wrappers SECURITY DEFINER, got %s INVOKER', v_count);
END$$;

BEGIN;
INSERT INTO content.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000099', 'wrap@test');

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000099';
  v_res jsonb;
BEGIN
  -- Call via the public wrapper; should match wiki.list_index output.
  v_res := public.wiki_list_index(v_user, NULL);
  ASSERT v_res = '[]'::jsonb, 'public wrapper should return empty array for new user';

  v_res := public.wiki_get_user_context('wrap@test');
  ASSERT (v_res->>'found')::boolean, 'public get_user_context wrapper should find user';
END$$;
ROLLBACK;
