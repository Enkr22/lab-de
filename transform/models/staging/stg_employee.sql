-- Empleados (personas).
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    EmployeeId        as employee_id,
    FirstName         as first_name,
    LastName          as last_name,
    BirthDate         as birth_date,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'employee') }}
qualify row_number() over (partition by EmployeeId order by UpdatedAt desc, load_id desc) = 1
