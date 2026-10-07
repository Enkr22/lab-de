-- SCD tipo 2: una fila por versión del sueldo de cada contratación.
-- La historia se reconstruye desde la nómina (gaps and islands):
--   1. Sueldo mensual pagado en cada periodo (P001 x periodos por mes).
--   2. Marcar los periodos donde el sueldo cambió.
--   3. La suma acumulada de las marcas numera las versiones.
--   4. Cada versión vale desde su primer periodo hasta el día antes de la siguiente.
-- La versión 1 nunca arranca antes de la primera nómina que tenemos:
-- censura por la izquierda, no inventamos historia.

with salary_by_period as (
    select
        m.employment_id,
        p.start_date as period_start,
        m.amount * case c.pay_frequency when 'BIWEEKLY' then 2 else 1 end as monthly_salary
    from {{ ref('stg_payroll_movement') }} as m
    join {{ ref('stg_payroll_concept') }} as pc
        on pc.concept_id = m.concept_id
       and pc.concept_code = 'P001'
    join {{ ref('stg_payroll_period') }} as p on p.period_id = m.period_id
    join {{ ref('stg_country') }}        as c on c.country_code = p.country_code
),

changes as (
    select
        *,
        case when monthly_salary = lag(monthly_salary) over w then 0 else 1 end as is_change
    from salary_by_period
    window w as (partition by employment_id order by period_start)
),

versions as (
    select
        *,
        sum(is_change) over (partition by employment_id order by period_start
                             rows unbounded preceding) as version
    from changes
),

salary_versions as (
    select employment_id, version, monthly_salary, min(period_start) as first_period_start
    from versions
    group by all
),

with_valid_from as (
    select
        sv.*,
        case when sv.version = 1 then greatest(e.hire_date, sv.first_period_start)
             else sv.first_period_start
        end as valid_from
    from salary_versions as sv
    join {{ ref('stg_employment') }} as e on e.employment_id = sv.employment_id
)

select
    md5(concat_ws('|', v.employment_id, v.version))                    as employee_sk,
    v.employment_id,
    e.employee_id,
    emp.first_name || ' ' || emp.last_name                             as full_name,
    d.country_code,
    d.department_name,
    e.job_title,
    e.hire_date,
    e.termination_date,
    e.termination_reason,
    v.version,
    v.monthly_salary,
    v.valid_from,
    coalesce((lead(v.valid_from) over w) - 1, date '9999-12-31')       as valid_to,
    (lead(v.valid_from) over w) is null                                as is_current,
    min(v.valid_from) over (partition by v.employment_id) > e.hire_date as history_truncated
from with_valid_from as v
join {{ ref('stg_employment') }} as e   on e.employment_id = v.employment_id
join {{ ref('stg_employee') }}   as emp on emp.employee_id = e.employee_id
join {{ ref('stg_department') }} as d   on d.department_id = e.department_id
window w as (partition by v.employment_id order by v.valid_from)
