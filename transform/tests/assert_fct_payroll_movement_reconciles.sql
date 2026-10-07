-- Prueba singular: un SELECT en un archivo que debe regresar cero filas.
-- Falla si el join point-in-time pierde o duplica movimientos.
select s.n as staging_rows, f.n as mart_rows
from (select count(*) as n from {{ ref('stg_payroll_movement') }}) as s
cross join (select count(*) as n from {{ ref('fct_payroll_movement') }}) as f
where s.n <> f.n
