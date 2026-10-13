-- Grano: un movimiento de nómina (contratación x periodo x concepto).
-- Join point-in-time: cada movimiento se liga a la versión del empleado
-- vigente cuando se pagó.
--
-- Modelo INCREMENTAL: la primera corrida (o con --full-refresh) construye la
-- tabla completa. Las siguientes solo procesan los movimientos recientes y los
-- integran por movement_id: si la fila ya existía se reemplaza, si es nueva se
-- agrega (delete+insert). Por eso reprocesar una fila no la duplica.
{{
    config(
        materialized='incremental',
        unique_key='movement_id',
        incremental_strategy='delete+insert'
    )
}}

select
    m.movement_id,
    de.employee_sk,
    m.employment_id,
    m.concept_id                                    as concept_key,
    p.country_code,
    m.period_id,
    cast(strftime(p.pay_date, '%Y%m%d') as integer) as pay_date_key,
    m.amount,
    m.amount * dc.sign                              as signed_amount,
    m.updated_at
from {{ ref('stg_payroll_movement') }} as m
join {{ ref('stg_payroll_period') }}   as p  on p.period_id = m.period_id
join {{ ref('stg_employment') }}       as e  on e.employment_id = m.employment_id
join {{ ref('dim_concept') }}          as dc on dc.concept_key = m.concept_id
join {{ ref('dim_employee') }}         as de
    on de.employment_id = m.employment_id
   and greatest(p.start_date, e.hire_date) between de.valid_from and de.valid_to

{% if is_incremental() %}
-- Ventana de traslape de 3 días: reprocesa un poco de más para no perder
-- filas que llegaron tarde. Gracias al unique_key, reprocesar no duplica.
where m.updated_at >= (select max(t.updated_at) - interval 3 day from {{ this }} as t)
{% endif %}
