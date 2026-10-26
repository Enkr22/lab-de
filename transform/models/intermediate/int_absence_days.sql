-- Capa intermedia: las incidencias que cuentan, partidas en días.
-- Grano: un renglón por incidencia por día. Todavía PUEDE haber dos renglones
-- para la misma contratación y el mismo día (empalmes); eso lo resuelve el mart.
-- Reglas de RH (DATA-1425) que se aplican aquí:
--   1. Solo incidencias aprobadas.
--   2. Solo días dentro de la contratación (alta <= día <= baja).

with approved as (
    select absence_id, employment_id, absence_type, start_date, end_date
    from {{ ref('stg_absence') }}
    where status = 'APPROVED'
),

-- Partir cada rango en días: tu Query D (CROSS APPLY + GENERATE_SERIES), en DuckDB
absence_days as (
    select
        a.absence_id,
        a.employment_id,
        a.absence_type,
        cast(g.day as date) as absence_date
    from approved as a
    cross join lateral generate_series(a.start_date, a.end_date, interval 1 day) as g(day)
)

select
    ad.absence_id,
    ad.employment_id,
    ad.absence_type,
    ad.absence_date,
    cast(strftime(ad.absence_date, '%Y%m%d') as integer) as date_key
from absence_days as ad
join {{ ref('stg_employment') }} as e
  on e.employment_id = ad.employment_id
where ad.absence_date >= e.hire_date
  and (e.termination_date is null or ad.absence_date <= e.termination_date)