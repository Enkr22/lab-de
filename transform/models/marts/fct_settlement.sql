-- Grano: un finiquito. Las líneas se pivotean a columnas con
-- agregación condicional (sum de case).
select
    s.settlement_id,
    de.employee_sk,
    s.employment_id,
    d.country_code,
    cast(strftime(e.termination_date, '%Y%m%d') as integer) as termination_date_key,
    cast(strftime(s.settlement_date, '%Y%m%d') as integer)  as settlement_date_key,
    e.termination_reason,
    s.status,
    sum(case when pc.concept_code = 'F002' then sl.amount else 0 end)             as vacation_amount,
    sum(case when pc.concept_code = 'F001' then sl.amount else 0 end)             as indemnity_amount,
    sum(case when pc.concept_type = 'DEDUCTION' then sl.amount else 0 end)        as deductions_amount,
    sum(sl.amount * case pc.concept_type when 'EARNING' then 1 else -1 end)       as net_amount
from {{ ref('stg_settlement') }}       as s
join {{ ref('stg_employment') }}       as e  on e.employment_id = s.employment_id
join {{ ref('stg_department') }}       as d  on d.department_id = e.department_id
join {{ ref('stg_settlement_line') }}  as sl on sl.settlement_id = s.settlement_id
join {{ ref('stg_payroll_concept') }}  as pc on pc.concept_id = sl.concept_id
join {{ ref('dim_employee') }}         as de
    on de.employment_id = s.employment_id
   and e.termination_date between de.valid_from and de.valid_to
group by all
