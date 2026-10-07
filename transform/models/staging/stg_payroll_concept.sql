-- Conceptos de nómina.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    ConceptId         as concept_id,
    CountryCode       as country_code,
    Code              as concept_code,
    Name              as concept_name,
    ConceptType       as concept_type,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'payroll_concept') }}
qualify row_number() over (partition by ConceptId order by UpdatedAt desc, load_id desc) = 1
