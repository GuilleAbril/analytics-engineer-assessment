# Code Review — `models/marts/mart_top_accounts.sql`

Análisis detallado para usar al rellenar el bloque `-- ISSUES FOUND` y al reescribir el modelo (Part 2 del README).

## Modelo original (transcrito)

```sql
select
    e.account_id,
    a.account_name,
    a.industry,
    sum(e.revenue_influenced) as total_revenue,
    count(*) as total_events,
    sum(e.revenue_influenced) / count(*) as revenue_per_event
from {{ source('raw', 'raw_events') }} e
left join {{ source('raw', 'raw_accounts') }} a on e.account_id = a.account_id
where e.event_date >= '2024-01-01'
group by 1, 2, 3
order by total_revenue desc
limit 10
```

## Intent declarado
> "Top 10 accounts by total revenue influenced (by client)."

## Issues (ordenadas por severidad)

### Críticas (correctness / multi-tenant)

1. **No hay `client_id` en SELECT ni en JOIN ni en GROUP BY.** El intent dice "by client" — el modelo debe mostrar el top-10 *por cliente*, no un top-10 global. Falta `client_id` en el output, falta `partition by client_id` y falta `client_id` en el join. **Esto es un data leak entre tenants** además de devolver un resultado incorrecto.

2. **`limit 10` global en lugar de top-N por cliente.** Aunque añadiéramos `client_id` al SELECT, `limit 10` seguiría siendo global. Hay que usar `row_number() over (partition by client_id order by total_revenue_influenced desc)` y filtrar por `rank <= 10`.

3. **Join sólo por `account_id`** sin condicionar por `client_id`. Si un mismo `account_id` existiera para dos clientes (o hubiera basura en raw), juntarías eventos de un tenant con la cuenta de otro. Debe ser `on e.account_id = a.account_id and e.client_id = a.client_id`.

### Importantes (calidad / KPI mal definido)

4. **`revenue_per_event` está mal calculado.** Divide la suma de revenue (sólo poblada en `form_fill` y `meeting_booked`) entre `count(*)` de *todos* los eventos, incluyendo impressions y clicks que nunca aportan revenue. El ratio se diluye proporcionalmente al volumen de top-of-funnel y deja de ser interpretable. Opciones: (a) eliminarlo, (b) renombrarlo y dividir sólo por eventos de conversión.

5. **Lee `source()` directamente desde un mart.** Rompe la separación staging→marts requerida por el README. Debe leer `ref('stg_events')` y `ref('stg_accounts')`.

6. **Fecha hardcoded `'2024-01-01'`.** No parametrizable, envejece mal. Usar `{{ var('reference_date', 'current_date') }}` con una ventana razonable (ej. último año) o documentar que es all-time y quitar el filtro.

### Estructurales (mantenibilidad)

7. **LEFT JOIN sobre accounts pero el GROUP BY incluye `account_name` e `industry`.** Si un evento tiene un `account_id` no presente en `raw_accounts`, esas columnas colapsan a NULL y aparece una fila fantasma "NULL, NULL" agregando varios accounts huérfanos. Debe ser INNER JOIN (un evento sin account válido es un dato roto que merece un test de `relationships`, no una fila en el mart).

8. **Sin tests ni documentación.** El modelo no tiene entrada en `models/marts/_models.yml` ni columnas descritas. Requisito mínimo del README.

### Menores / nice-to-have

- `count(*)` no distingue entre `revenue_influenced is null` y `not null`. Usar `count(*) filter (where is_conversion_event)` o equivalentes sería más expresivo.
- Sin `config()` ni materialización explícita (hereda `+materialized: table` del project — OK).
- `total_revenue` debería llamarse `total_revenue_influenced` para coincidir con la terminología del README y del resto de modelos.
- `order by total_revenue desc` antes del `limit` es redundante una vez introduzcamos `row_number`; mantener un `order by client_id, account_rank` final para presentación.

## Plantilla de bloque `-- ISSUES FOUND`

Al rellenar el comentario en el archivo, mantén las 8 issues principales en lenguaje compacto (una línea cada una) y deja las "menores" como bullets adicionales o las integras en la reescritura sin mencionarlas. Ejemplo:

```sql
-- ============================================================
-- ISSUES FOUND:
-- 1. Missing client_id everywhere (output, join, group by) — multi-tenant data leak; "top by client" intent not met.
-- 2. `limit 10` returns top-10 globally, not per client. Needs row_number() partition by client_id.
-- 3. Join condition omits client_id — could mix accounts across tenants if account_id collides.
-- 4. `revenue_per_event` divides by all events incl. impressions/clicks (which carry no revenue) — KPI is meaningless.
-- 5. Reads source() directly from a mart — violates staging→marts separation.
-- 6. Hardcoded date '2024-01-01' — not parameterized, ages badly.
-- 7. LEFT JOIN on accounts produces NULL group rows for orphan events; should be INNER JOIN.
-- 8. No tests, no YAML documentation entry.
-- ============================================================
```

## Reescritura sugerida (esqueleto)

```sql
{{ config(
    tags=['accounts'],
    -- prod (BigQuery): cluster_by=['client_id'] — multi-tenant access pattern
) }}

with events as (
    select
        client_id,
        account_id,
        revenue_influenced,
        is_conversion_event
    from {{ ref('stg_events') }}
    where event_date >= dateadd('day', -365, {{ var('reference_date', 'current_date') }})
),
accounts as (
    select client_id, account_id, account_name, industry
    from {{ ref('stg_accounts') }}
),
agg as (
    select
        e.client_id,
        e.account_id,
        a.account_name,
        a.industry,
        sum(e.revenue_influenced)                              as total_revenue_influenced,
        count(*) filter (where e.is_conversion_event)          as total_conversion_events
    from events e
    inner join accounts a
        on e.account_id = a.account_id
       and e.client_id  = a.client_id
    group by 1, 2, 3, 4
),
ranked as (
    select
        *,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc nulls last
        ) as account_rank
    from agg
)
select
    client_id,
    account_id,
    account_name,
    industry,
    total_revenue_influenced,
    total_conversion_events,
    account_rank
from ranked
where account_rank <= 10
order by client_id, account_rank
```
