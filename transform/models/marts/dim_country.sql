-- Países con su moneda y frecuencia de pago.
select
    country_code,
    country_name,
    currency_code,
    pay_frequency
from {{ ref('stg_country') }}
