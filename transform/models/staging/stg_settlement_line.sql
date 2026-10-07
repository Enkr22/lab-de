-- Líneas de finiquito.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    SettlementLineId  as settlement_line_id,
    SettlementId      as settlement_id,
    ConceptId         as concept_id,
    Amount            as amount,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'settlement_line') }}
qualify row_number() over (partition by SettlementLineId order by UpdatedAt desc, load_id desc) = 1
