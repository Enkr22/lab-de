-- Contrataciones.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    EmploymentId      as employment_id,
    EmployeeId        as employee_id,
    DepartmentId      as department_id,
    JobTitle          as job_title,
    MonthlySalary     as monthly_salary,
    HireDate          as hire_date,
    TerminationDate   as termination_date,
    TerminationReason as termination_reason,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'employment') }}
qualify row_number() over (partition by EmploymentId order by UpdatedAt desc, load_id desc) = 1
