{{ config(severity = 'warn') }}
-- Regla de RH #2: no existen ausencias fuera de la contratación.
-- El modelo ya las excluye; esta prueba AVISA cuántas siguen llegando
-- del origen (bug conocido del endpoint móvil).
select a.absence_id, a.employment_id, a.start_date, a.end_date,
       e.hire_date, e.termination_date
from {{ ref('stg_absence') }} as a
join {{ ref('stg_employment') }} as e
  on e.employment_id = a.employment_id
where a.status = 'APPROVED'
  and (a.start_date < e.hire_date
       or (e.termination_date is not null and a.end_date > e.termination_date))