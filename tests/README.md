# Tests

Plain SQL suites, one file per RPC cluster. Runner: `scripts/run-tests.sh`.

Each test file:
- Wraps everything in a transaction (`BEGIN; ... ROLLBACK;`) so files are independent.
- Uses `DO $$ ... $$` blocks with `ASSERT` / `RAISE EXCEPTION` on failure.
- Loads fixtures via inlined `SELECT` + `INSERT` — no shared fixture file required, keeps each test self-contained and readable.

Failures propagate as psql exit codes; the runner reports per-file pass/fail.

## Run

```bash
make reset   # fresh db, migrations applied
make test
```

Or together: `make reset && make test`.

## Writing new tests

```sql
BEGIN;

-- arrange
INSERT INTO content.users (id, email) VALUES ('...', '...');
SELECT wiki.upsert_article('{...}'::jsonb);

-- act + assert
DO $$
DECLARE
  v_result jsonb;
BEGIN
  v_result := wiki.list_index('...'::uuid, NULL);
  ASSERT jsonb_array_length(v_result) = 1, 'expected 1 article';
END$$;

ROLLBACK;
```
