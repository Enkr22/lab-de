-- Departamentos.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    DepartmentId      as department_id,
    CountryCode       as country_code,
    Name              as department_name,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'department') }}
qualify row_number() over (partition by DepartmentId order by UpdatedAt desc, load_id desc) = 1
