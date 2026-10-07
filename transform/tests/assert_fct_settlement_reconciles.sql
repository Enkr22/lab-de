-- Falla si algún finiquito se pierde o se duplica en el mart.
select s.n as staging_rows, f.n as mart_rows
from (select count(*) as n from {{ ref('stg_settlement') }}) as s
cross join (select count(*) as n from {{ ref('fct_settlement') }}) as f
where s.n <> f.n
