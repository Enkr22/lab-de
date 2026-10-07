-- Finiquitos (encabezado).
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    SettlementId      as settlement_id,
    EmploymentId      as employment_id,
    SettlementDate    as settlement_date,
    Status            as status,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'settlement') }}
qualify row_number() over (partition by SettlementId order by UpdatedAt desc, load_id desc) = 1
