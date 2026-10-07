-- 03_gold_facts.sql
-- Tablas de hechos de la capa gold. Requisito: 02_gold_dims.sql.

-- ---------------------------------------------------------------------------
-- fct_payroll_movement
-- Grano: un movimiento de nómina (contratación x periodo x concepto).
--
-- El join a dim_employee es "point-in-time": cada movimiento se liga a la
-- versión del empleado que estaba vigente cuando se pagó. Así, un análisis
-- de 2023 ve el sueldo de 2023, no el de hoy. Es para lo que existe una SCD2.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold.fct_payroll_movement AS
SELECT
    m.MovementId                                   AS movement_id,
    de.employee_sk,
    m.EmploymentId                                 AS employment_id,
    m.ConceptId                                    AS concept_key,
    p.CountryCode                                  AS country_code,
    m.PeriodId                                     AS period_id,
    CAST(strftime(p.PayDate, '%Y%m%d') AS INTEGER) AS pay_date_key,
    m.Amount                                       AS amount,
    m.Amount * dc.sign                             AS signed_amount
FROM silver.payroll_movement AS m
JOIN silver.payroll_period   AS p  ON p.PeriodId = m.PeriodId
JOIN silver.employment       AS e  ON e.EmploymentId = m.EmploymentId
JOIN gold.dim_concept        AS dc ON dc.concept_key = m.ConceptId
JOIN gold.dim_employee       AS de
    ON de.employment_id = m.EmploymentId
   -- Si el alta fue a mitad del periodo, la versión vigente arranca en el alta
   AND greatest(p.StartDate, e.HireDate) BETWEEN de.valid_from AND de.valid_to;

-- ---------------------------------------------------------------------------
-- fct_settlement
-- Grano: un finiquito. Las líneas se convierten en columnas con
-- agregación condicional (SUM de CASE): un pivote escrito a mano.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold.fct_settlement AS
SELECT
    s.SettlementId                                         AS settlement_id,
    de.employee_sk,
    s.EmploymentId                                         AS employment_id,
    d.CountryCode                                          AS country_code,
    CAST(strftime(e.TerminationDate, '%Y%m%d') AS INTEGER) AS termination_date_key,
    CAST(strftime(s.SettlementDate, '%Y%m%d') AS INTEGER)  AS settlement_date_key,
    e.TerminationReason                                    AS termination_reason,
    s.Status                                               AS status,
    SUM(CASE WHEN pc.Code = 'F002' THEN sl.Amount ELSE 0 END)              AS vacation_amount,
    SUM(CASE WHEN pc.Code = 'F001' THEN sl.Amount ELSE 0 END)              AS indemnity_amount,
    SUM(CASE WHEN pc.ConceptType = 'DEDUCTION' THEN sl.Amount ELSE 0 END)  AS deductions_amount,
    SUM(sl.Amount * CASE pc.ConceptType WHEN 'EARNING' THEN 1 ELSE -1 END) AS net_amount
FROM silver.settlement      AS s
JOIN silver.employment      AS e  ON e.EmploymentId = s.EmploymentId
JOIN silver.department      AS d  ON d.DepartmentId = e.DepartmentId
JOIN silver.settlement_line AS sl ON sl.SettlementId = s.SettlementId
JOIN silver.payroll_concept AS pc ON pc.ConceptId = sl.ConceptId
JOIN gold.dim_employee      AS de
    ON de.employment_id = s.EmploymentId
   AND e.TerminationDate BETWEEN de.valid_from AND de.valid_to
GROUP BY ALL;

-- Reconciliación: el mismo número de filas en silver y en gold.
-- Si el join point-in-time perdiera filas, gold tendría menos;
-- si dos versiones se traslaparan, gold tendría más.
SELECT 'fct_payroll_movement' AS table_name,
       (SELECT COUNT(*) FROM silver.payroll_movement)   AS silver_rows,
       (SELECT COUNT(*) FROM gold.fct_payroll_movement) AS gold_rows
UNION ALL
SELECT 'fct_settlement',
       (SELECT COUNT(*) FROM silver.settlement),
       (SELECT COUNT(*) FROM gold.fct_settlement);
