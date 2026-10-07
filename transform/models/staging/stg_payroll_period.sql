-- Periodos de nómina.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    PeriodId          as period_id,
    CountryCode       as country_code,
    StartDate         as start_date,
    EndDate           as end_date,
    PayDate           as pay_date,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'payroll_period') }}
qualify row_number() over (partition by PeriodId order by UpdatedAt desc, load_id desc) = 1
