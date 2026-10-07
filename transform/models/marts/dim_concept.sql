-- Conceptos de nómina. sign materializa la decisión de diseño del día 2:
-- el origen guarda montos positivos y aquí se aplica el signo.
select
    concept_id   as concept_key,
    country_code,
    concept_code,
    concept_name,
    concept_type,
    case concept_type when 'EARNING' then 1 else -1 end as sign
from {{ ref('stg_payroll_concept') }}
