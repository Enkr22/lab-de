-- Regla de RH #3: cada contratación aparece UNA sola vez por día.
-- Falla si algún día quedó contado dos veces (un empalme sin resolver).
select employment_id, absence_date, count(*) as rows_per_day
from {{ ref('fct_absence_day') }}
group by employment_id, absence_date
having count(*) > 1
