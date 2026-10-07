-- 02_gold_dims.sql
-- Dimensiones de la capa gold. Son tablas (no vistas): se reconstruyen
-- completas en cada corrida (full refresh). Requisito: 01_silver.sql.

CREATE SCHEMA IF NOT EXISTS gold;

-- ---------------------------------------------------------------------------
-- dim_date: un renglón por día. Misma técnica que el calendario de periodos:
-- generar la serie de fechas y derivar columnas.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold.dim_date AS
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER) AS date_key,
    CAST(d AS DATE)                        AS full_date,
    year(d)                                AS year,
    quarter(d)                             AS quarter,
    month(d)                               AS month,
    monthname(d)                           AS month_name,
    day(d)                                 AS day,
    dayofweek(d)                           AS day_of_week,   -- 0 = domingo
    dayofweek(d) IN (0, 6)                 AS is_weekend
FROM generate_series(DATE '2015-01-01', DATE '2026-12-31', INTERVAL 1 DAY) AS t(d);

-- ---------------------------------------------------------------------------
-- dim_country y dim_concept: catálogos con nombres de negocio.
-- sign materializa tu decisión de diseño del día 2: el origen guarda montos
-- positivos, y "otro proceso hace las cuentas". Este es ese proceso.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold.dim_country AS
SELECT
    CountryCode  AS country_code,
    Name         AS country_name,
    CurrencyCode AS currency_code,
    PayFrequency AS pay_frequency
FROM silver.country;

CREATE OR REPLACE TABLE gold.dim_concept AS
SELECT
    ConceptId   AS concept_key,
    CountryCode AS country_code,
    Code        AS concept_code,
    Name        AS concept_name,
    ConceptType AS concept_type,
    CASE ConceptType WHEN 'EARNING' THEN 1 ELSE -1 END AS sign
FROM silver.payroll_concept;

-- ---------------------------------------------------------------------------
-- dim_employee: SCD tipo 2. Una fila por cada versión del sueldo de cada
-- contratación, con su vigencia (valid_from, valid_to).
--
-- El origen sobrescribe el sueldo, así que la historia se reconstruye desde
-- la nómina: el sueldo base pagado (P001) en cada periodo dice cuál era el
-- sueldo vigente en ese momento. Es un problema clásico de "gaps and islands":
--   1. Sueldo mensual pagado en cada periodo.
--   2. Marcar los periodos donde el sueldo cambió respecto al anterior.
--   3. La suma acumulada de esas marcas numera las versiones.
--   4. Cada versión empieza en su primer periodo y termina un día antes
--      de que empiece la siguiente.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold.dim_employee AS
WITH salary_by_period AS (
    SELECT
        m.EmploymentId AS employment_id,
        p.StartDate    AS period_start,
        m.Amount * CASE c.PayFrequency WHEN 'BIWEEKLY' THEN 2 ELSE 1 END AS monthly_salary
    FROM silver.payroll_movement AS m
    JOIN silver.payroll_concept AS pc ON pc.ConceptId = m.ConceptId AND pc.Code = 'P001'
    JOIN silver.payroll_period  AS p  ON p.PeriodId = m.PeriodId
    JOIN silver.country         AS c  ON c.CountryCode = p.CountryCode
),
changes AS (
    SELECT
        *,
        -- El primer periodo compara contra NULL, así que siempre cuenta como cambio
        CASE WHEN monthly_salary = LAG(monthly_salary) OVER w THEN 0 ELSE 1 END AS is_change
    FROM salary_by_period
    WINDOW w AS (PARTITION BY employment_id ORDER BY period_start)
),
versions AS (
    SELECT
        *,
        SUM(is_change) OVER (PARTITION BY employment_id ORDER BY period_start
                             ROWS UNBOUNDED PRECEDING) AS version
    FROM changes
),
salary_versions AS (
    SELECT employment_id, version, monthly_salary, MIN(period_start) AS first_period_start
    FROM versions
    GROUP BY ALL
),
with_valid_from AS (
    SELECT
        sv.*,
        -- La primera versión arranca en el alta, aunque haya sido a mitad de periodo
        CASE WHEN sv.version = 1 THEN e.HireDate ELSE sv.first_period_start END AS valid_from
    FROM salary_versions AS sv
    JOIN silver.employment AS e ON e.EmploymentId = sv.employment_id
)
SELECT
    -- Llave sustituta determinista: la misma versión produce la misma llave
    -- en cada reconstrucción, a diferencia de un ROW_NUMBER.
    md5(concat_ws('|', v.employment_id, v.version)) AS employee_sk,
    v.employment_id,
    e.EmployeeId                                   AS employee_id,
    emp.FirstName || ' ' || emp.LastName           AS full_name,
    d.CountryCode                                  AS country_code,
    d.Name                                         AS department_name,
    e.JobTitle                                     AS job_title,
    e.HireDate                                     AS hire_date,
    e.TerminationDate                              AS termination_date,
    e.TerminationReason                            AS termination_reason,
    v.version,
    v.monthly_salary,
    v.valid_from,
    COALESCE(
        LEAD(v.valid_from) OVER (PARTITION BY v.employment_id ORDER BY v.valid_from) - 1,
        DATE '9999-12-31'
    ) AS valid_to,
    LEAD(v.valid_from) OVER (PARTITION BY v.employment_id ORDER BY v.valid_from) IS NULL AS is_current
FROM with_valid_from AS v
JOIN silver.employment AS e   ON e.EmploymentId = v.employment_id
JOIN silver.employee   AS emp ON emp.EmployeeId = e.EmployeeId
JOIN silver.department AS d   ON d.DepartmentId = e.DepartmentId;

-- Resumen
SELECT
    (SELECT COUNT(*) FROM gold.dim_employee)                      AS employee_versions,
    (SELECT COUNT(DISTINCT employment_id) FROM gold.dim_employee) AS employments,
    (SELECT COUNT(*) FROM gold.dim_employee WHERE is_current)     AS current_versions,
    (SELECT COUNT(*) FROM gold.dim_date)                          AS dates,
    (SELECT COUNT(*) FROM gold.dim_concept)                       AS concepts,
    (SELECT COUNT(*) FROM gold.dim_country)                       AS countries;
