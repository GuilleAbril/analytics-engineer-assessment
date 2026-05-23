# Octane11 Analytics Engineer Assessment — Plan de Implementación

> **Audiencia:** modelo ejecutor (Sonnet) que va a implementar los entregables del [README.md](../../README.md).
> **Fecha de referencia:** 2026-05-23 (afecta a las ventanas relativas tipo "últimos 90 días").
> **Adapter:** dbt-duckdb. El profile en uso es `octane11_analytics_claude_2` y el DB local es `octane11_analytics_claude_2.duckdb`.
>
> Antes de tocar nada, lee [skills/using-dbt-for-analytics-engineering/SKILL.md](../../.claude/skills/using-dbt-for-analytics-engineering/SKILL.md) y [skills/running-dbt-commands/SKILL.md](../../.claude/skills/running-dbt-commands/SKILL.md). Si necesitas añadir tests unitarios usa `adding-dbt-unit-test`. Si dudas de sintaxis dbt, consulta `fetching-dbt-docs`.

---

## 1. Filosofía y criterios de diseño

El README evalúa **modeling decisions, SQL quality, dbt structure, performance, window functions, code review y reasoning**. Optimiza por *claridad* y *justificabilidad* sobre completitud.

Principios que vamos a seguir:

1. **Capas explícitas**: `staging → intermediate → marts`. Sólo staging usa `source()`; intermediate y marts usan `ref()`.
2. **Granularidad nombrada**: cada mart deja claro en su nombre el grain (`mart_<tema>_<grain>_<ventana>`).
3. **Multi-tenant first**: nunca agregamos sin `client_id`. Cualquier join cross-cliente es un bug (data leak entre tenants). Los joins eventos↔cuentas deben condicionarse también por `client_id` igualado, no sólo por `account_id`.
4. **Conversion-event awareness**: `revenue_influenced` sólo está poblado en `form_fill` y `meeting_booked`. Nunca uses `count(*)` como denominador de ratios de revenue.
5. **Optimizaciones aunque DuckDB las ignore**: añadimos `partition_by` / `cluster_by` / `incremental_strategy` en los `config()` con comentario `-- BigQuery: ...`. DuckDB las ignora silenciosamente; la justificación queda en código y se puede explicar en el debrief.
6. **Tests con intención**: cada mart al menos lleva una `unique_combination_of_columns` sobre su PK compuesta + `not_null` en las dimensiones clave. Tests "decorativos" no aportan.
7. **Fechas parametrizadas**: la ventana "últimos 90 días" se calcula con `{{ var('reference_date', "current_date") }}` para que el reviewer pueda fijar la fecha si la corre meses más tarde y los datos vuelvan a quedar fuera de ventana.

---

## 2. Arquitectura objetivo

```
seeds (raw_*)
  │
  ▼
models/staging/        ← 1 modelo por raw, casteos y renames, sin lógica de negocio
  stg_campaigns        (ya existe — referencia)
  stg_accounts
  stg_events
  stg_ad_spend         (Parte 3 — opcional)
  │
  ▼
models/intermediate/   ← lógica de negocio reusable, no expuesta al consumidor
  int_events_enriched          (events + campaigns: añade channel, client del campaign)
  int_campaign_performance     (agregados por campaign: meetings, revenue, etc.)
  │
  ▼
models/marts/          ← entregables, una pregunta de negocio por modelo
  mart_top_channels_per_client_last_90d   (Q1)
  mart_account_engagement_monthly         (Q2)
  mart_efficient_campaigns                (Q3)
  mart_top_accounts                       (Part 2 — reescritura)
  mart_campaign_budget_vs_spend           (Part 3 — opcional)
```

### Por qué esta separación

- **Staging** sólo castea/renombra → predecible, testeable, evita repetir casts.
- **Intermediate** existe porque tres marts distintos (Q1, Q3 y Part 3) necesitan `events × campaigns` con `channel`. Sin la capa intermedia esa join se repetiría tres veces — cualquier corrección habría que hacerla N veces.
- **Marts** son delgados: básicamente window functions + filtros + presentación. Esto los hace fáciles de revisar contra la pregunta de negocio.

### Materializaciones

| Capa | Default | Excepciones |
|---|---|---|
| staging | `table` (ya configurado en `dbt_project.yml`) | `stg_events` candidato a `incremental` (ver §5) |
| intermediate | `view` | `int_events_enriched` puede pasar a `table` si crece — ahora es trivial |
| marts | `table` | — |

---

## 3. Modelos detallados

### 3.1 Staging

#### `stg_accounts.sql`
- Fuente: `source('raw', 'raw_accounts')`
- Casts: `employee_count` → `integer`. Resto strings.
- Añade `employee_size_band` (`small <50`, `mid 50–500`, `enterprise >500`) — útil para análisis futuros y demuestra criterio.
- Filtra `where account_id is not null`.

#### `stg_events.sql`
- Fuente: `source('raw', 'raw_events')`
- Casts: `event_date` → `date`, `revenue_influenced` → `decimal(18,2)`.
- Añade columna booleana `is_conversion_event` = `event_type in ('form_fill','meeting_booked')`. Hace muchos marts más legibles.
- Filtra `where event_id is not null and campaign_id is not null and account_id is not null`.
- **Config (incremental opcional):**
  ```jinja
  {{ config(
      materialized='incremental',
      unique_key='event_id',
      incremental_strategy='delete+insert',
      partition_by={'field': 'event_date', 'data_type': 'date', 'granularity': 'day'},
      cluster_by=['client_id', 'campaign_id']
  ) }}
  ```
  - Filtro incremental con **ventana de re-procesamiento de 7 días** para datos late-arriving:
    ```sql
    {% if is_incremental() %}
      where event_date >= (select dateadd('day', -7, max(event_date)) from {{ this }})
    {% endif %}
    ```
  - Justificación en comentario: "BigQuery: partition by day on `event_date`, cluster by `client_id, campaign_id`. Estrategia de late data: re-escribimos las últimas 7 particiones cada run."

### 3.2 Intermediate

#### `int_events_enriched.sql`
- `view`
- `stg_events e` LEFT JOIN `stg_campaigns c` ON `e.campaign_id = c.campaign_id AND e.client_id = c.client_id` (joinear también por `client_id` previene cross-tenant si hubiera datos sucios).
- Expone: todas las columnas de event + `channel`, `campaign_name`, `budget`, `start_date`, `end_date` desde campaign.

#### `int_campaign_performance.sql`
- `view`
- Agrega por `campaign_id` (con `client_id`, `channel`, `campaign_name`, `budget` arrastrados):
  - `total_events`
  - `total_impressions`, `total_clicks`, `total_form_fills`, `total_meetings_booked` (usando `count(*) filter (where event_type = ...)`)
  - `total_revenue_influenced` (sum)
- Sirve a Q3 y a Part 3 sin recalcular.

### 3.3 Marts — Preguntas de negocio

#### Q1 — `mart_top_channels_per_client_last_90d.sql`

Output: `client_id, channel, total_revenue_influenced, channel_rank` (top 3 por cliente).

```sql
with base as (
    select client_id, channel, revenue_influenced
    from {{ ref('int_events_enriched') }}
    where is_conversion_event
      and event_date >= dateadd('day', -90, {{ var('reference_date', 'current_date') }})
),
agg as (
    select
        client_id,
        channel,
        sum(revenue_influenced) as total_revenue_influenced
    from base
    group by 1, 2
),
ranked as (
    select
        client_id,
        channel,
        total_revenue_influenced,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc
        ) as channel_rank
    from agg
)
select * from ranked where channel_rank <= 3
```

**Notas técnicas:**
- `row_number` (no `rank`) para evitar empates que devuelvan >3 filas por cliente. Documentar el trade-off (empates rotos arbitrariamente vs. >3 filas).
- BigQuery config sugerida (en comentario): `cluster_by=['client_id']`.

#### Q2 — `mart_account_engagement_monthly.sql`

Output: `client_id, account_id, event_month, total_events, prev_month_events, mom_change`.

```sql
with monthly as (
    select
        client_id,
        account_id,
        date_trunc('month', event_date) as event_month,
        count(*) as total_events
    from {{ ref('stg_events') }}
    group by 1, 2, 3
)
select
    client_id,
    account_id,
    event_month,
    total_events,
    lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    ) as prev_month_events,
    total_events - lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    ) as mom_change
from monthly
```

**Notas:**
- Decisión consciente: **NO** rellenamos meses vacíos con 0. Si un account no tiene eventos en un mes, simplemente no hay fila, y `lag` saltará al mes anterior con datos. Documentar esta decisión en el YAML del modelo — el stakeholder puede preferir el contrario. Si lo pide, se generaría una spine de `(client × account × month)`.
- `prev_month_events` y `mom_change` serán `NULL` para el primer mes de cada account. Esto es esperado, no un bug. Test: `mom_change` not_null sólo para `event_month > min(event_month) over (partition by ...)`.
- BigQuery config sugerida (en comentario): `partition_by={'field':'event_month','data_type':'date','granularity':'month'}`, `cluster_by=['client_id', 'account_id']`.

#### Q3 — `mart_efficient_campaigns.sql`

Output: `client_id, campaign_id, campaign_name, channel, budget, meetings_booked, cost_per_meeting, avg_cost_per_meeting_for_channel`. Sólo campañas con meetings_booked > 0; resultado son las campañas que están *por encima* de su peer set ⇒ filtrar `cost_per_meeting < avg_cost_per_meeting_for_channel`.

```sql
with cp as (
    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget,
        total_meetings_booked as meetings_booked,
        budget / nullif(total_meetings_booked, 0) as cost_per_meeting
    from {{ ref('int_campaign_performance') }}
    where total_meetings_booked > 0
),
with_avg as (
    select
        *,
        avg(cost_per_meeting) over (partition by channel) as avg_cost_per_meeting_for_channel
    from cp
)
select *
from with_avg
where cost_per_meeting < avg_cost_per_meeting_for_channel
```

**Decisión a documentar:** "outperforming peers" se interpreta como **por debajo del coste medio del canal** (más eficiente = menor coste por meeting). Si el stakeholder lo entiende como otra cosa (ej. ratio relativo, percentile), pediríamos confirmación. El filtro final hace que `cost_per_meeting < avg_cost_per_meeting_for_channel` siempre se cumpla — el modelo es accionable directamente.

### 3.4 Part 2 — `mart_top_accounts.sql` (reescritura)

Lee [.claude/plans/CODE_REVIEW.md](CODE_REVIEW.md) para la lista exhaustiva de issues. Los puntos clave a corregir:

1. **Falta `client_id`**: en multi-tenant, "top 10 accounts" sin partición por cliente es un data leak.
2. **`limit 10` global** en lugar de top-10 *por cliente*. Usar `row_number() over (partition by client_id order by total_revenue desc)`.
3. **Fecha hardcoded** (`'2024-01-01'`). Sustituir por `var('reference_date')` o eliminar y dejar all-time con doc.
4. **Lee `source()` en mart**: debería leer `ref('stg_*')`.
5. **`revenue_per_event` mal calculado**: divide entre todos los eventos incluyendo impressions/clicks (sin revenue). El KPI sólo tiene sentido sobre eventos de conversión, o se elimina.
6. **Join sólo por `account_id`**: debería ser por `account_id AND client_id` para preservar tenant boundaries.
7. **LEFT JOIN + GROUP BY de account_name/industry**: si la cuenta no existe los grupos colapsan en NULL — usar INNER JOIN (un evento sin account válido es un dato roto, no algo que mostrar).
8. **Sin tests ni docs**.

Lista las 8 issues como comentario `-- ISSUES FOUND` (formato del template) y luego escribe la versión corregida bajo `-- YOUR IMPROVED VERSION`. La versión nueva debe seguir el mismo patrón que los otros marts (window function, ref a staging, filtro por reference_date, top-N por cliente).

### 3.5 Part 3 (opcional) — `mart_campaign_budget_vs_spend.sql`

Solo abordar si los anteriores están terminados y testeados.

**Setup del parquet en DuckDB** (documentar en README o en `docs/PARQUET_SETUP.md`):

Opción recomendada — `external_location` en source via meta para dbt-duckdb:

```yaml
# models/staging/_sources.yml
sources:
  - name: external
    schema: main
    meta:
      external_location: "read_parquet('{{ project_dir }}/data/{name}.parquet')"
    tables:
      - name: ad_spend
```

> dbt-duckdb resuelve `{name}` por el nombre de la table. Verificar con `fetching-dbt-docs` si la sintaxis exacta de la versión instalada espera `{{ project_dir }}` o ruta relativa. Alternativa segura: macro custom que devuelva `read_parquet('data/ad_spend.parquet')`.

Modelos:
- `stg_ad_spend.sql` — casts + renames.
- `mart_campaign_budget_vs_spend.sql` — join `stg_campaigns` con agregado de `stg_ad_spend` por campaign_id:
  - `variance = budget - total_actual_spend`
  - `variance_pct = variance / nullif(budget, 0)`
  - `status = case when variance < 0 then 'over_budget' else 'under_budget' end`

---

## 4. Tests (mínimo 2 — vamos a poner bastantes más)

Documentar en YAML por carpeta (`models/staging/_models.yml`, `models/intermediate/_models.yml`, `models/marts/_models.yml`).

**Staging:**
- `stg_accounts.account_id` — `unique`, `not_null`
- `stg_events.event_id` — `unique`, `not_null`
- `stg_events.event_type` — `accepted_values: ['impression','click','form_fill','meeting_booked']`
- `stg_events.campaign_id` — `relationships` a `stg_campaigns.campaign_id`
- `stg_events.account_id` — `relationships` a `stg_accounts.account_id`

**Marts:**
- `mart_top_channels_per_client_last_90d` — `dbt_utils.unique_combination_of_columns: [client_id, channel]`; `channel_rank` entre 1 y 3 (test `accepted_values` o test custom).
- `mart_account_engagement_monthly` — `dbt_utils.unique_combination_of_columns: [client_id, account_id, event_month]`.
- `mart_efficient_campaigns` — `campaign_id` unique; `meetings_booked > 0` (test custom singular en `tests/`).
- `mart_top_accounts` — `dbt_utils.unique_combination_of_columns: [client_id, account_id]`.

**Docs:**
- Al menos `mart_top_channels_per_client_last_90d` documentado en YAML con descripción del modelo, granularidad, definición de cada columna y ventana temporal. Idealmente todos los marts.

---

## 5. Optimizaciones de "BigQuery" (a documentar aunque DuckDB las ignore)

Añadir en cada `config()` con comentario `-- prod (BigQuery):` que explique el por qué. Resumen:

| Modelo | partition_by | cluster_by | materialization | Justificación |
|---|---|---|---|---|
| `stg_events` | `event_date` (day) | `client_id, campaign_id` | `incremental` (delete+insert, ventana 7d) | Tabla de mayor cardinalidad y con patrón append-mostly; el partition pruning ayuda en todas las ventanas temporales |
| `mart_account_engagement_monthly` | `event_month` (month) | `client_id, account_id` | `table` | Queries por client/account/mes |
| `mart_top_channels_per_client_last_90d` | — | `client_id` | `table` | Conjunto pequeño; clustering por tenant |
| `mart_efficient_campaigns` | — | `channel, client_id` | `table` | Pequeño; clustering ayuda a filtros típicos |

**Late-arriving data strategy a explicar en debrief:**
- Estrategia: ventana móvil de re-procesamiento (`delete+insert` de los últimos N días). N=7 cubre la mayoría de retrasos típicos del adapter de eventos. Si vinieran eventos con más de 7 días de retraso, se manejan vía full-refresh manual programado.
- Alternativa más estricta: `merge` con `unique_key=event_id` y filtro de ventana amplia — más costoso pero idempotente perfecto.

---

## 6. Orden de ejecución (paso a paso para el modelo ejecutor)

1. **Verificar entorno**
   - Confirmar que `dbt deps` ya está hecho (`dbt_packages/` existe — sí está).
   - Ejecutar `dbt seed` si la DB no contiene las tablas.
   - Ejecutar `dbt run --select stg_campaigns` para verificar conectividad.
2. **Staging**
   - Crear `models/staging/stg_accounts.sql` y `models/staging/stg_events.sql`.
   - Actualizar `models/staging/_sources.yml` añadiendo columnas faltantes (`account_id`, `client_id` etc.).
   - Actualizar `models/staging/_models.yml` con descripciones y tests.
   - `dbt build --select staging` y verificar 0 fallos.
3. **Intermediate**
   - Crear `models/intermediate/int_events_enriched.sql` e `int_campaign_performance.sql`.
   - Crear `models/intermediate/_models.yml`.
   - Añadir bloque `intermediate` al `dbt_project.yml`:
     ```yaml
     intermediate:
       +materialized: view
       +schema: intermediate
       +tags: ['intermediate']
     ```
   - `dbt build --select intermediate`.
4. **Marts — preguntas de negocio**
   - Crear Q1, Q2, Q3 (en ese orden — Q1 es el más simple).
   - Crear `_models.yml` (reemplazar el vacío) con docs y tests.
   - `dbt build --select marts`.
5. **Part 2 — code review**
   - Editar `models/marts/mart_top_accounts.sql`:
     - Rellenar el bloque `-- ISSUES FOUND` con las 8 issues de [CODE_REVIEW.md](CODE_REVIEW.md).
     - Reescribir el SELECT bajo `-- YOUR IMPROVED VERSION`.
   - Añadir entrada en `_models.yml`.
   - `dbt build --select mart_top_accounts`.
6. **Part 3 (opcional)** — sólo si lo anterior está verde.
7. **Verificación final**
   - `dbt build` (toda la cadena, todos los tests).
   - `dbt show --select mart_top_channels_per_client_last_90d --limit 10` (y los otros marts) para validar resultados a ojo.
   - Confirmar que el output tiene las columnas exactas que pide el README.

---

## 7. Detalles que conviene NO olvidar

- **Profile mismatch sospechoso**: el `dbt_project.yml` apunta a `octane11_analytics_claude_2` y `profiles.yml` declara `octane11_analytics_claude_2`. Coinciden. Sin tocar.
- **`mart_top_accounts._models.yml`** está vacío (`models: []`). Hay que rellenarlo.
- **`stg_events` no existe todavía** — la `relationships` test desde events hacia accounts/campaigns sólo funcionará después de crear los staging.
- **El `.duckdb` ya existe** (`octane11_analytics_claude_2.duckdb`, 4MB). Está en `.gitignore`. Si algo se ve raro, `dbt clean && dbt seed` reinicia.
- **`current_date` en DuckDB** devuelve la fecha local del sistema. Para tests reproducibles, definir `var('reference_date')` en `dbt_project.yml` o pasarlo en CLI (`--vars '{reference_date: "2026-05-23"}'`). Documentar el default elegido.
- **No mostrar emojis ni hacer commits salvo que se pida explícitamente.**
- **No usar `select *` en marts** (sí en CTEs intermedios). Lista columnas explícitamente en la SELECT final de cada mart.

---

## 8. Checklist de "Definition of Done"

- [ ] Todos los staging existen y `dbt build --select staging` pasa.
- [ ] Intermediate creados y construyen sin error.
- [ ] Q1, Q2, Q3 devuelven las columnas exactas del README.
- [ ] `mart_top_accounts` reescrito con bloque de issues + nueva versión.
- [ ] `_models.yml` de marts documenta al menos un modelo y declara tests para todos.
- [ ] `dbt build` completo (run + test) sin fallos.
- [ ] `dbt show` manual de cada mart devuelve filas y números plausibles (no 0 filas, no NULLs masivos).
- [ ] Configs de partition/cluster/incremental añadidas con comentario `-- prod (BigQuery)`.
- [ ] Decisiones no triviales (lag sin spine, row_number vs rank, ventana de 7d para late data, interpretación de "outperforming") documentadas en YAML o comentario de modelo.
