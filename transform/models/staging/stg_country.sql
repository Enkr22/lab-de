-- Países.
-- Patrón de staging: la versión más reciente de cada fila y nombres en snake_case.
select
    CountryCode       as country_code,
    Name              as country_name,
    CurrencyCode      as currency_code,
    PayFrequency      as pay_frequency,
    CreatedAt         as created_at,
    UpdatedAt         as updated_at,
    load_id           as _load_id
from {{ source('bronze', 'country') }}
qualify row_number() over (partition by CountryCode order by UpdatedAt desc, load_id desc) = 1
