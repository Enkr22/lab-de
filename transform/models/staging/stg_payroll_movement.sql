-- Movimientos de nómina.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    MovementId        as movement_id,
    EmploymentId      as employment_id,
    PeriodId          as period_id,
    ConceptId         as concept_id,
    Amount            as amount,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'payroll_movement') }}
qualify row_number() over (partition by MovementId order by UpdatedAt desc, load_id desc) = 1
