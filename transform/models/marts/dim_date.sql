-- Un renglón por día, de 2015 a 2026.
-- Misma técnica que el calendario de periodos: generar la serie y derivar columnas.
select
    cast(strftime(d, '%Y%m%d') as integer) as date_key,
    cast(d as date)                        as full_date,
    year(d)                                as year,
    quarter(d)                             as quarter,
    month(d)                               as month,
    monthname(d)                           as month_name,
    day(d)                                 as day,
    dayofweek(d)                           as day_of_week,   -- 0 = domingo
    dayofweek(d) in (0, 6)                 as is_weekend
from generate_series(date '2015-01-01', date '2026-12-31', interval 1 day) as t(d)
