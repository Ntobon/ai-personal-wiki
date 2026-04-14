# Personal Wiki — Plan

Karpathy-style LLM wiki en Supabase. Consumido por agentes (Claude Code ambos perfiles, claude.ai mobile/web, future workers). **Sin UI humana.** Mirrors `content-queue` conventions.

## Filosofía

Tres ops, auto-enriquecimiento continuo, sin RAG:

1. **Ingest** — pull de fuentes existentes (reading queue, digests, actions, Claude Code logs de ambos perfiles, Notion, repos). Update artículos relacionados; crea nuevos solo con substance real.
2. **Query** — agente lee `wiki.list_index` + artículos completos relevantes (no chunks). **Escribe insights de vuelta** como artículos nuevos o secciones. El self-compacting loop.
3. **Lint** — checks inline baratos en cada write + audit batched periódico. Activo desde MVP, no diferido.

**Retrieval:** Postgres FTS (`tsvector` + `pg_trgm`) sobre artículos completos. No chunking, no embeddings en v1. pgvector queda como fase-2 si FTS se queda corto.

**Tono:** Wikipedia, no AI voice. Short sentences. Attribution, not assertion. Max 2 direct quotes por artículo.

## Multi-profile architecture

Dos Claude Code profiles:
- `~/.claude` — **MOLT (work)** — alias `ccd` / `claude-molt`
- `~/.claude-personal` — **Personal** — alias `ccp` / `claude-personal`

Cada perfil corre con `CLAUDE_CONFIG_DIR` distinto → skills separados, MCPs separados, logs separados en `~/.claude/projects/*` vs `~/.claude-personal/projects/*`.

**Decisión:** UN solo wiki, en personal Supabase (`wjypineoplzwayvktorc`). Usuario es partner de MOLT → sin issue de compliance. Ambos perfiles escriben a la misma base. Mobile (claude.ai con cuenta personal) conecta vía MCP al mismo Supabase → ve todo filtrado por scope.

**Constraint crítico:** Supabase MCP es single-org. El perfil MOLT tiene su Supabase MCP apuntando a la org MOLT y **no puede agregar un segundo MCP Supabase** para personal org. Perfil MOLT no puede leer/escribir personal Supabase directamente vía MCP oficial.

**Solución — wiki-proxy MCP (custom stdio server):**
Construimos un MCP server propio que corre local como stdio. Expone tools `wiki_*` (upsert, search, read, etc.). Internamente habla con personal Supabase usando credenciales locales. El perfil MOLT agrega este proxy a su `.mcp.json` como server adicional (convive con el MCP Supabase de MOLT porque son servers distintos). Perfil personal y mobile pueden usar Supabase MCP directo (ya conectado a personal org) o el proxy — abstraemos el transport dentro de los skills.

Ventajas clave:
- Tools aparecen nativos en ambos profiles, mismo UX
- Credenciales personales viven en archivo local, MOLT profile nunca las maneja
- Post-MVP: mismo codebase se puede exponer como HTTP MCP en Cloud Run para futuros workers o mobile con tools custom
- El Supabase MCP de MOLT sigue apuntando a MOLT org sin conflicto

**Requisitos de config:**
- Personal profile: Supabase MCP → personal org (ya existe) + wiki-proxy MCP (opcional, redundante)
- MOLT profile: Supabase MCP → MOLT org (ya existe) + **wiki-proxy MCP → personal Supabase vía stdio**
- Mobile claude.ai: Supabase MCP → personal org (ya existe) — suficiente
- Credenciales personales en `~/.claude-personal/wiki-proxy/config.json` (owned por user, 0600)
- Skills del wiki instalados en **ambos** `~/.claude/skills/` y `~/.claude-personal/skills/`
- Skills detectan profile y eligen transport: personal/mobile → Supabase MCP directo; MOLT → wiki-proxy MCP

## Architecture

```
Supabase personal (wjypineoplzwayvktorc — compartido con content-queue, finance-tracker)
└── wiki schema (NEW — separado de content.* y public.*)
    ├── articles              (el wiki — markdown + FTS vector + scope)
    ├── links                 (backlinks precomputados)
    ├── sources               (log de qué se ingestó, idempotencia)
    ├── aliases               (dedup: "Alex" = "Alejandro" = "alex")
    ├── corrections           (feedback loop — correcciones del usuario)
    ├── retrieval_log         (feedback loop — qué buscó el agente, qué encontró)
    ├── rejected_writebacks   (feedback loop — write-backs descartados)
    └── lint_runs             (registro de lints ejecutados, findings, fixes)

Skills (editados en este repo, copiados a ambos profiles, pushed a Notion vía /skill-push)
├── wiki-ingest    pull + compile desde fuentes
├── wiki-ask       query con write-back + correction detection
├── wiki-lint      audit batched (contradicciones, orphans, stale)
└── wiki-review    reporte mensual accionable (fase tardía)

wiki-proxy/       custom MCP server (stdio) — puente MOLT → personal Supabase
├── src/          TypeScript, @modelcontextprotocol/sdk
├── bin/server    entry point que MOLT spawnea
└── config.json   credenciales personal (en ~/.claude-personal/wiki-proxy/)
```

Agentes hablan con Supabase vía MCP:
- Personal profile / mobile → Supabase MCP oficial (personal org)
- MOLT profile → wiki-proxy MCP (stdio local)

RPCs son la API — skills nunca tocan tablas directo. El transport (MCP oficial vs proxy) se abstrae dentro de cada skill.

## Schema sketch

```sql
wiki.articles (
  id uuid primary key default gen_random_uuid(),
  slug text unique,
  title text not null,
  type text not null,                  -- person | project | concept | decision | tool
  scope text not null,                 -- personal | molt | shared
  content_md text not null,
  summary text not null,               -- 1-2 líneas para el index
  tags text[] default '{}',
  aliases text[] default '{}',
  sources jsonb default '[]'::jsonb,
  manually_edited boolean default false,
  last_manual_edit_at timestamptz,
  last_retrieved_at timestamptz,       -- feedback: usage-based pruning
  search_vector tsvector generated always as (
    setweight(to_tsvector('spanish', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(aliases,' '),'')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(summary,'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(tags,' '),'')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(content_md,'')), 'D')
  ) stored,
  user_id uuid not null references content.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

wiki.links (
  from_article uuid references wiki.articles(id) on delete cascade,
  to_article   uuid references wiki.articles(id) on delete cascade,
  context text,
  primary key (from_article, to_article)
);

wiki.sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references content.users(id),
  source_type text,                    -- queue_item | digest | action_item | claude_log_personal | claude_log_molt | repo | notion_skill | manual
  source_id text,
  source_scope text,                   -- hint para scope tagging
  ingested_at timestamptz default now(),
  articles_touched uuid[] default '{}'
);

wiki.corrections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references content.users(id),
  article_id uuid references wiki.articles(id),
  original_claim text,
  corrected_claim text,
  reason text,
  detected_in text,                    -- 'wiki-ask' | 'manual'
  corrected_at timestamptz default now()
);

wiki.retrieval_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references content.users(id),
  query text,
  scope_filter text,
  results_count int,
  articles_returned uuid[] default '{}',
  user_accepted boolean,               -- NULL hasta que haya señal
  asked_at timestamptz default now()
);

wiki.rejected_writebacks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references content.users(id),
  proposed_content text,
  rejection_reason text,
  rejected_at timestamptz default now()
);

wiki.lint_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references content.users(id),
  started_at timestamptz default now(),
  finished_at timestamptz,
  findings jsonb,
  fixes_applied jsonb
);

create index articles_fts     on wiki.articles using gin (search_vector);
create index articles_tags    on wiki.articles using gin (tags);
create index articles_trgm    on wiki.articles using gin (content_md gin_trgm_ops);
create index articles_scope   on wiki.articles (user_id, scope);
create index articles_lastret on wiki.articles (user_id, last_retrieved_at);
```

Triggers: auto `updated_at`. No RLS en v1 (single user; enforce vía `user_id` en RPCs, mirror content-queue).

## RPCs (la API)

| Function | Purpose |
|---|---|
| `wiki.get_user_context(email)` | Bootstrap — contrato tipo `content.get_user_context` |
| `wiki.list_index(user_id, scope)` | Lista liviana: slug+title+summary+tags. Reemplaza `index.md`. |
| `wiki.read_article(user_id, slug)` | Artículo completo + outbound links + backlinks. Actualiza `last_retrieved_at`. |
| `wiki.search(user_id, query, scope, limit)` | FTS + trigram fallback, rankeado. Loggea a `retrieval_log`. |
| `wiki.find_by_alias(user_id, name, type?)` | Dedup lookup durante ingest |
| `wiki.upsert_article(...)` | Compile step escribe aquí; preserva `manually_edited=true` salvo forzado |
| `wiki.rebuild_links(article_id)` | Scan `[[wikilinks]]` en content_md, refresh `wiki.links` |
| `wiki.log_source(...)` | Registrar ingesta; idempotencia |
| `wiki.recent_ingests(user_id, limit)` | Vista cronológica de compile activity |
| `wiki.orphans(user_id)` | Artículos sin inbound ni outbound links |
| `wiki.record_correction(...)` | Aplicar corrección del usuario; update artículo + log |
| `wiki.reject_writeback(...)` | Registrar write-back rechazado para aprendizaje |
| `wiki.lint_summary(user_id)` | Devuelve findings de últimos lints + métricas de health |

Todas retornan `jsonb`. Naming mirrors `content.*`.

## Skills

Cada skill tiene frontmatter `platform: both` o `claude-code` según capabilities.

### `wiki-ingest` — platform: both (con fuentes segmentadas)
Pull-based compile. Triggers: `/wiki-ingest`, "compile wiki", scheduled.

**Fuentes cloud-accessible (ambos clientes, ambos profiles):**
- `content.queue_items`, `content.digests`, `content.action_items`
- Notion (personal + MOLT workspace si existe)
- MOLT Supabase (si tiene tablas relevantes)

**Fuentes local-only (solo Claude Code del perfil correspondiente):**
- `~/.claude-personal/projects/*.jsonl` — logs de perfil Personal
- `~/.claude/projects/*.jsonl` — logs de perfil MOLT
- `~/personal/*` y `~/molt/*` repos (READMEs, CLAUDE.md, memory files)

**Flujo:**
1. Bootstrap (config → memory → user context)
2. Detectar platform; para cada fuente accesible, query "new since last `wiki.log_source`"
3. Bucket cronológico del material crudo
4. Por cada entry: scope inference (logs personal → `personal`, logs MOLT → `molt`, repos por path, etc.)
5. Find_by_alias → update existente o crear nuevo
6. **Regla dura: 3+ oraciones significativas o no se crea artículo**
7. **Checks inline (lint shift-left):**
   - Antes de crear → trigram match para evitar duplicados
   - Después de write → `rebuild_links` del artículo tocado
   - Verificar contradicción obvia con artículo existente
8. Preservar `manually_edited=true` salvo flag explícito
9. `wiki.log_source` al final — idempotente en replay

### `wiki-ask` — platform: both
Query con write-back + correction detection. Triggers: preguntas con contexto personal, "ask the wiki".

**Flujo:**
1. `wiki.search(query, scope)` → top 3-5 artículos por rank
2. Para cada hit: `wiki.read_article` (full content + links)
3. Opcional: seguir 1-2 niveles de backlinks si la respuesta spans topics
4. Sintetizar respuesta, citar por slug
5. **Detección de corrección inline** — si el siguiente turn del usuario niega algo ("no, es X", "estás equivocado", "en realidad"), llamar `wiki.record_correction`
6. **Write-back step** — si la síntesis produjo conexiones/claims nuevos no triviales:
   - Validar regla de 3+ oraciones
   - Trigram match contra existentes
   - Si pasa filtros → crear/actualizar artículo con `sources: [{type: 'ask_writeback', confidence: ...}]`
   - Si el usuario rechaza ("no archives eso") → `wiki.reject_writeback`
7. `wiki.retrieval_log` siempre — para medir hit rate

### `wiki-lint` — platform: both (pref. Claude Code)
Audit batched. Triggers: `/wiki-lint`, scheduled semanal, user request.

**Checks:**
- Contradicciones cross-article (parallel subagents, batches de 5)
- Orphans (`wiki.orphans`)
- Stale claims (articles no actualizados en 6+ meses pero sources referenciados)
- Alias collisions
- Broken `[[wikilinks]]`
- Write-backs de bajo confidence → propone merge o delete
- Articles con `last_retrieved_at` > 3 meses → candidatos a prune

Escribe findings a `wiki.lint_runs`. Propone fixes; aplica los de alto confidence si tú apruebas batch.

### `wiki-review` — platform: both (fase tardía)
Reporte mensual accionable. Triggers: `/wiki-review`, scheduled mensual.

**Contenido:**
- `corrections` — qué tipo de errores está cometiendo compile, señal para ajustar prompt
- `rejected_writebacks` — qué tipo de write-back rechazaste más
- `retrieval_log` — queries sin resultados, señal de qué fuente falta
- Health metrics: articles created, updated, orphaned, retrieved
- Top-5 findings accionables con fix propuesto

## Scheduled triggers

Vía `/schedule` (Anthropic-side triggers):

- **Diario cloud-only ingest** — `wiki-ingest --sources=queue,digests,actions,notion`. No depende de filesystem; corre server-side.
- **Semanal lint** — `wiki-lint`. Cloud-only también; pura lógica sobre DB.
- **Mensual review** — `wiki-review`. Genera reporte, te lo entrega.

Para fuentes locales (logs Claude Code, repos): hook Stop en cada profile que corre `wiki-ingest --sources=local` al cerrar sesión. O invocación manual `ccp /wiki-ingest --local` / `ccd /wiki-ingest --local`. MVP arranca manual, pasa a hook después.

## Repo structure (mirrors content-queue)

```
personal-wiki/
├── CLAUDE.md              # conventions + bootstrap + skill table + platform awareness
├── CLAUDE.local.md        # PR skill, local-only rules
├── README.md              # qué es, setup, skill table
├── config.json            # git-ignored: project_id + email
├── config.example.json    # template
├── schema.sql             # full DDL + RPCs (reference copy)
├── migrations/
│   └── 001_initial.sql
├── skills/
│   ├── wiki-ingest/SKILL.md
│   ├── wiki-ask/SKILL.md
│   ├── wiki-lint/SKILL.md
│   └── wiki-review/SKILL.md (fase tardía)
├── wiki-proxy/            # custom MCP server (stdio) — puente MOLT → personal
│   ├── src/
│   │   ├── index.ts       # MCP server entry (stdio transport)
│   │   ├── tools.ts       # definiciones de wiki_upsert_article, wiki_search, etc.
│   │   └── supabase.ts    # cliente PostgREST o supabase-js
│   ├── package.json
│   ├── tsconfig.json
│   └── bin/server         # ejecutable que MOLT profile spawnea
├── scripts/               # backfill, dry-run compile, profile-sync helper
├── setup/SETUP.md         # incluye: MCP config en ambos profiles, skill install, proxy install
├── plan/
│   ├── PLAN.md            # este archivo trimmed
│   ├── PHASE-1-SCAFFOLD.md
│   ├── PHASE-2-SCHEMA.md
│   ├── PHASE-2B-PROXY.md  # MCP proxy server (antes de skills para validar transport)
│   ├── PHASE-3-INGEST-MVP.md
│   ├── PHASE-4-ASK.md
│   ├── PHASE-5-LINT.md
│   ├── PHASE-6-SCHEDULED.md
│   ├── PHASE-7-EXPAND-CLOUD.md
│   ├── PHASE-8-CLAUDE-LOGS.md
│   ├── PHASE-9-NOTION-REPOS.md
│   └── PHASE-10-REVIEW.md
└── .claude/settings.json  # allow Supabase MCP + wiki-proxy MCP + local bash
```

## Execution order

| Phase | What | Effort | Gate |
|---|---|---|---|
| 1 | Scaffold repo, CLAUDE.md, config, ambos `.claude/settings.json` | S | estructura creada, skills stub instalados en ambos profiles |
| 2 | Schema + RPCs completos (inc. tablas de feedback) + migration + apply | M | `wiki.list_index` retorna array vacío sin error |
| 2b | **wiki-proxy MCP server (stdio)** — TypeScript, expone tools `wiki_*` | M | desde MOLT profile: `mcp__wiki-proxy__list_index` retorna array vacío sin error |
| 3 | `wiki-ingest` MVP — solo reading queue + checks inline + transport abstraction (MCP oficial vs proxy) | L | 50 queue items → ~15-25 artículos desde perfil personal; igual funcionamiento desde perfil MOLT vía proxy |
| 4 | `wiki-ask` con write-back + corrección + retrieval log | M | "qué sabemos de Farzapedia?" → síntesis grounded + log en `retrieval_log` (ambos profiles + mobile) |
| 5 | `wiki-lint` skill completo | M | primer lint sobre 100+ articles produce findings accionables |
| 6 | Scheduled triggers cloud-only vía `/schedule` | S | trigger diario corre sin intervención |
| 7 | Expand ingest a digests + action items (cloud) | M | artículos se enriquecen, no solo broadean |
| 8 | **Ingest de Claude Code logs — AMBOS profiles** | L | logs filtrados por scope (`personal` vs `molt`), ruido minimizado |
| 9 | Ingest Notion + repos (READMEs, CLAUDE.md, memory) | M | tool/knowledge sections del wiki populadas |
| 10 | `wiki-review` mensual | M | primer review report es útil y accionable |
| 11 | (futuro) wiki-proxy expuesto como HTTP MCP en Cloud Run | M | workers remotos / mobile con tools custom pueden consumir |

**MVP = fases 1-5** (incluye proxy en 2b). Fase 8 (logs de ambos profiles) es alto valor y no opcional — alimenta la mayor parte de tu uso diario de Claude Code. No se posterga más de lo necesario. Fase 11 es opcional, solo si aparece necesidad de cloud workers.

## Key decisions

1. **Un solo wiki en personal Supabase.** Usuario es partner MOLT → sin compliance issue. Simplifica todo. Ambos profiles conectan: personal vía Supabase MCP oficial, MOLT vía wiki-proxy MCP custom.
2. **wiki-proxy MCP (custom stdio server) resuelve el conflict single-org del Supabase MCP oficial.** MOLT profile no puede tener dos MCPs Supabase (uno MOLT-org, otro personal-org) — el proxy expone tools `wiki_*` como servidor distinto. Credenciales personales en archivo local (0600), MOLT profile nunca las maneja directo. Transport se abstrae dentro de skills. Post-MVP: mismo codebase reutilizable como HTTP MCP para cloud workers.
3. **Scope field desde día 1** (`personal | molt | shared`). Filtrado en queries; tagging por heurística + LLM en compile.
4. **Supabase + FTS, no pgvector, no files, no GitHub.** Latencia <100ms, mobile-friendly, cero infra nueva. pgvector si FTS se queda corto en fase futura.
5. **Whole articles, not chunks.** FTS rankea artículos, agente lee markdown completo.
6. **Karpathy > Farza en core loop.** Tres ops, query-writes-back es central. Farza's guardrails en los márgenes (3+ oraciones, Wikipedia tone, update antes de crear).
7. **Lint desde MVP**, no diferido. Inline en ingest/ask + skill batched en fase 5.
8. **Skills instalados en ambos profiles** (`~/.claude/skills/` + `~/.claude-personal/skills/`). Source of truth en este repo; `cp` a ambos destinos + `/skill-push` a Notion.
9. **Platform awareness en cada skill.** `wiki-ingest` tiene fuentes cloud (both) y locales (Claude Code por profile); transport (MCP oficial vs proxy) se abstrae internamente.
10. **Feedback loops tabla-backed** (corrections, retrieval_log, rejected_writebacks, lint_runs). Acumula señal para auto-corrección real.
11. **Mobile = personal account → ve todo filtrado por scope.** Sin federación, sin complejidad cross-account.
12. **Ingest idempotente via `wiki.sources`.** Replay sin duplicar.
13. **Manual edits ganan por default** (`manually_edited=true`).
14. **No RLS en v1.** Match sibling projects. Agregar si algún día compartimos.

## Platform awareness (matrix)

| Capability | Claude Code Personal | Claude Code MOLT | claude.ai Mobile/Web |
|---|---|---|---|
| Supabase MCP oficial → personal org | ✅ conectado | ❌ bloqueado (MCP ya en MOLT org) | ✅ conectado |
| wiki-proxy MCP (stdio) → personal Supabase | ✅ (opcional, redundante) | ✅ **única vía de acceso al wiki** | ❌ (no stdio en cloud) |
| Read + write wiki | ✅ vía MCP oficial | ✅ vía wiki-proxy | ✅ vía MCP oficial |
| Notion MCP | ✅ personal workspace | ✅ MOLT workspace | ✅ personal |
| Filesystem (logs, repos) | ✅ `~/.claude-personal/*` | ✅ `~/.claude/*` | ❌ |
| Scheduled triggers | vía `/schedule` | vía `/schedule` | vía `/schedule` |
| Hooks (Stop) | ✅ | ✅ | ❌ |
| Skills wiki-* | instalados | instalados | instalados |

## Feedback loops (resumen)

1. **Correcciones conversacionales** — detectadas inline en `wiki-ask`, persistidas a `wiki.corrections`, aplicadas al artículo.
2. **Retrieval misses** — log en `wiki.retrieval_log`; review mensual reporta queries sin resultados → señal de fuente faltante.
3. **Usage-based pruning** — `last_retrieved_at` en articles; lint marca stale candidates para delete/merge.
4. **Write-back calibration** — cada write-back flaggeado con confidence; lint audita los de bajo confidence; user puede rechazar → `wiki.rejected_writebacks`.
5. **Meta-loop mensual** — `wiki-review` presenta findings accionables: patrones de error, gaps, write-backs rechazados, ajustes de prompt sugeridos.

## Open questions

- **FTS config**: `spanish` vs `simple` vs `english`. Contenido es mixto. Default `spanish`; revisar con data real.
- **Agresividad del write-back en `wiki-ask`**: demasiado → wiki infla con basura; muy conservador → loop muere. Arrancar conservador (Claude confirma "archivar esto?") y relajar cuando heurísticas probadas.
- **Logs de Claude Code son ricos pero ruidosos.** Necesita filter prompt que extrae decisiones/razonamiento y descarta tool-call chatter. Iteración esperada en fase 8.
- **Dedup de personas/proyectos**: alias + trigram antes de crear. Edge case: "Alex" puede ser varias personas → `type=person` + disambiguator en slug (`alex-ramirez` vs `alex-cliente-molt`).
- **Scope inference desde logs**: log de `~/.claude/projects/` → `molt`, log de `~/.claude-personal/projects/` → `personal`. Claude en compile decide `shared` cuando aplica (herramientas, conceptos técnicos generales).
- **Cuándo pgvector justifica sumarse**: trigger si `wiki-ask` pierde artículos semánticamente relacionados por divergencia de vocabulario. Track miss rate 2-4 semanas post-MVP antes de decidir.
- **MOLT Supabase como fuente**: vale la pena ingestar desde su proyecto (si tiene datos estructurados útiles) o solo desde repos/logs? Decidir en fase 7.
- **wiki-proxy: TypeScript vs otro stack**: default TS por `@modelcontextprotocol/sdk` oficial. Alternativas: Python (`mcp` package), Bun (misma SDK, menor overhead de arranque). Decidir en fase 2b según preferencia de mantenimiento.
- **Credenciales del proxy**: service_role_key vs anon_key. service_role bypassa RLS (no tenemos RLS pero igual da más poder del necesario). Probable default: anon_key + RPCs con `SECURITY DEFINER` donde aplique. Revisar en fase 2b.
- **Versioning del wiki-proxy**: si evoluciona el schema, cómo versionamos el proxy para que MOLT profile no quede desalineado? Opción simple: el proxy chequea schema version al arranque y warnea. Definir en fase 2b.

## Next step

Fase 1: scaffold del repo. Propongo contenidos de `CLAUDE.md`, `config.example.json`, `README.md` stub, `.claude/settings.json`, `setup/SETUP.md` esqueleto. Review antes de escribir.

Retomamos después desde aquí.
