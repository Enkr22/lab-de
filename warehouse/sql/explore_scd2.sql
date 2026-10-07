-- explore_scd2.sql
-- La historia de sueldos de una persona en Argentina con el mayor número de
-- versiones: la historia que el origen sobrescribió, reconstruida en gold.

SELECT
    employment_id,
    full_name,
    version,
    monthly_salary,
    valid_from,
    valid_to,
    is_current
FROM gold.dim_employee
WHERE employment_id = (
    SELECT employment_id
    FROM gold.dim_employee
    WHERE country_code = 'AR'
    GROUP BY employment_id
    ORDER BY COUNT(*) DESC, employment_id
    LIMIT 1
)
ORDER BY version;
