-- Incidencias (vacaciones, incapacidades y faltas).
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
-- El grano sigue siendo el del origen: una fila por incidencia, con su rango.
select
    AbsenceId    as absence_id,
    EmploymentId as employment_id,
    AbsenceType  as absence_type,
    StartDate    as start_date,
    EndDate      as end_date,
    Status       as status,
    CreatedAt    as created_at,
    UpdatedAt    as updated_at,
    load_id      as _load_id
from {{ source('bronze', 'absence') }}
qualify row_number() over (partition by AbsenceId order by UpdatedAt desc, load_id desc) = 1