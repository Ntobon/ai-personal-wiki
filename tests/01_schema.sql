-- 01_schema.sql — schema, extensions, and critical indexes exist.

DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM pg_extension WHERE extname = 'pg_trgm';
  ASSERT v_count = 1, 'pg_trgm extension is not installed';

  SELECT count(*) INTO v_count FROM information_schema.schemata WHERE schema_name = 'wiki';
  ASSERT v_count = 1, 'wiki schema is missing';

  SELECT count(*) INTO v_count FROM information_schema.tables
   WHERE table_schema = 'wiki'
     AND table_name IN ('articles','links','sources','corrections',
                        'retrieval_log','rejected_writebacks','lint_runs');
  ASSERT v_count = 7, format('expected 7 wiki tables, got %s', v_count);

  SELECT count(*) INTO v_count FROM pg_indexes
   WHERE schemaname = 'wiki' AND indexname = 'articles_fts';
  ASSERT v_count = 1, 'articles_fts GIN index is missing';

  SELECT count(*) INTO v_count FROM pg_indexes
   WHERE schemaname = 'wiki' AND indexname IN ('articles_trgm','articles_title_trgm');
  ASSERT v_count = 2, 'trigram indexes on articles are missing';

  SELECT count(*) INTO v_count FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'wiki'
     AND p.proname IN ('get_user_context','list_index','read_article','search',
                       'find_by_alias','upsert_article','rebuild_links','log_source',
                       'recent_ingests','orphans','record_correction',
                       'reject_writeback','lint_summary');
  ASSERT v_count = 13, format('expected 13 wiki RPCs, got %s', v_count);
END$$;
