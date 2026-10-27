-- Grano: un renglón por contratación por día de ausencia.
-- Regla de RH (DATA-1425): un día cuenta una sola vez. Si dos incidencias
-- se empalman, gana SICK_LEAVE > VACATION > UNJUSTIFIED; entre dos del
-- mismo tipo (captura duplicada), la primera que se capturó.

with resolved as (
    select *
    from {{ ref('int_absence_days') }}
    qualify row_number() over (
        partition by employment_id, absence_date
        order by
            case absence_type
                when 'SICK_LEAVE'  then 1
                when 'VACATION'    then 2
                when 'UNJUSTIFIED' then 3
            end,
            absence_id
    ) = 1
)

select
    r.employment_id,
    r.absence_date,
    r.date_key,
    de.employee_sk,      -- la versión del empleado vigente ese día (point-in-time)
    de.country_code,
    r.absence_type,
    r.absence_id         -- la incidencia que "ganó" ese día, para rastrearla
from resolved as r
left join {{ ref('dim_employee') }} as de
  on de.employment_id = r.employment_id
 and r.absence_date between de.valid_from and de.valid_to
