-- Regla de RH #1: solo cuentan las incidencias aprobadas.
-- Falla si algún día del mart viene de una incidencia que no está APPROVED.
select f.employment_id, f.absence_date, a.absence_id, a.status
from {{ ref('fct_absence_day') }} as f
join {{ ref('stg_absence') }} as a
  on a.absence_id = f.absence_id
where a.status <> 'APPROVED'
