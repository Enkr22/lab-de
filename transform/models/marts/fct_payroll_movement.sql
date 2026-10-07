-- Grano: un movimiento de nómina (contratación x periodo x concepto).
-- Join point-in-time: cada movimiento se liga a la versión del empleado
-- vigente cuando se pagó.
select
    m.movement_id,
    de.employee_sk,
    m.employment_id,
    m.concept_id                                    as concept_key,
    p.country_code,
    m.period_id,
    cast(strftime(p.pay_date, '%Y%m%d') as integer) as pay_date_key,
    m.amount,
    m.amount * dc.sign                              as signed_amount
from {{ ref('stg_payroll_movement') }} as m
join {{ ref('stg_payroll_period') }}   as p  on p.period_id = m.period_id
join {{ ref('stg_employment') }}       as e  on e.employment_id = m.employment_id
join {{ ref('dim_concept') }}          as dc on dc.concept_key = m.concept_id
join {{ ref('dim_employee') }}         as de
    on de.employment_id = m.employment_id
   and greatest(p.start_date, e.hire_date) between de.valid_from and de.valid_to
