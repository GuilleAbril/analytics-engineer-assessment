### A opus 4.7:

Quiero que en base al README.md del proyecto que contiene los "requerimientos de negocio" generes el plan para crear la solución. 
Que definas bien la arquitectura, los modelos a crear y el por qué, los pasos a seguir, cualquier matización o definición técnica a mayores que veas necesario indicar para un modelo....etc. 
En la carpeta .claude/skills tienes lo necesario para trabajar adecuadamente con dbt.
Crea en la carpeta .claude, o donde creas que es necesario, lo que se necesite para que otro modelo (sonnet) lleve a cabo la ejecución/implementación del plan que has propuesto.
Y por último dame el prompt para pasarle al modelo que lo implementará a partir de lo que has creado, para resolver los "requerimientos de negocio".


### A sonnet 4.6:

"""
Estás trabajando en el directorio path_to_project\analytics-engineer-assessment-claude, un proyecto dbt (adapter: dbt-duckdb) para el assessment de Analytics Engineer de Octane11. Tu tarea es implementar la solución completa siguiendo el plan ya definido.

Antes de hacer nada:

Lee .claude/plans/IMPLEMENTATION_PLAN.md entero. Ese documento es la fuente de verdad — arquitectura, modelos, justificaciones, configs y orden de ejecución están ahí.
Lee .claude/plans/CODE_REVIEW.md antes de tocar models/marts/mart_top_accounts.sql.
Lee también README.md para tener presente el enunciado de negocio (no para redefinir nada — el plan ya lo traduce).
Carga las skills using-dbt-for-analytics-engineering y running-dbt-commands antes de empezar; usa adding-dbt-unit-test si añades tests unitarios y fetching-dbt-docs si dudas de sintaxis dbt o de dbt-duckdb (especialmente para Part 3).
Qué implementar (en este orden, validando con dbt build tras cada bloque):

Staging: stg_accounts, stg_events + actualizar _sources.yml y _models.yml.
Bloque intermediate en dbt_project.yml + carpeta models/intermediate/ con int_events_enriched e int_campaign_performance + su _models.yml.
Marts de las 3 preguntas: mart_top_channels_per_client_last_90d (Q1), mart_account_engagement_monthly (Q2), mart_efficient_campaigns (Q3). Rellena models/marts/_models.yml (actualmente vacío) con descripciones y tests.
Part 2: edita models/marts/mart_top_accounts.sql rellenando el bloque -- ISSUES FOUND con las 8 issues principales del CODE_REVIEW.md y escribe la versión corregida bajo -- YOUR IMPROVED VERSION. Añade su entrada en _models.yml.
Part 3 (opcional): sólo si todo lo anterior pasa dbt build limpio. Sigue la sección 3.5 del plan.
Reglas no negociables:

Marts y intermediate sólo leen vía ref(). Sólo staging usa source().
Cada agregación lleva client_id (multi-tenant). Cualquier join accounts ↔ events se condiciona por account_id AND client_id.
Output de cada mart debe tener exactamente las columnas que pide el README (mismos nombres, mismo orden).
Añade los config() con partition_by / cluster_by / incremental indicados en la sección 5 del plan, cada uno con un comentario -- prod (BigQuery): ... explicando el por qué.
Ventanas temporales relativas usan {{ var('reference_date', 'current_date') }}, no fechas hardcoded.
No hagas commits ni pushes a git. No introduzcas emojis en código. No expandas el alcance más allá de lo definido en el plan.
Trabaja desde la raíz del proyecto; el profile correcto es octane11_analytics_claude_2 (ya configurado).
Validación final (Definition of Done — sección 8 del plan): dbt build completo sin fallos, y dbt show --limit 10 de cada mart devolviendo filas plausibles. Reporta al final qué modelos se han creado, qué tests pasan, qué decisiones no triviales has tomado, y si has saltado Part 3 o no.