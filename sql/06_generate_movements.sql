/*
    06_generate_movements.sql
    Genera la historia de sueldos (aumentos anuales) y los movimientos de
    nómina de cada contratación en cada periodo en que estuvo activa.
    Requisito: 05_generate_employment.sql.

    Estrategia: full refresh de los movimientos. Antes de aplicar aumentos
    restaura el estado de contratación desde gen.EmploymentBase, así que
    re-ejecutarla no acumula aumentos sobre aumentos.

    Simplificaciones: un periodo con cualquier día activo se paga completo
    (sin prorrateo por días) y los aumentos aplican cada 1 de enero.
*/

USE LabNomina;
GO

/* ---------- 0. Foto del estado de contratación (propiedad del generador) ---------- */
-- Sin FK hacia payroll.Employment a propósito: la etapa 05 borra y recrea
-- contrataciones, y una FK aquí se lo impediría.
IF OBJECT_ID('gen.EmploymentBase', 'U') IS NULL
BEGIN
    CREATE TABLE gen.EmploymentBase (
        EmploymentId   INT           NOT NULL,
        BaseSalary     DECIMAL(18,2) NOT NULL,
        BaseUpdatedAt  DATETIME2(3)  NOT NULL,
        CONSTRAINT PK_EmploymentBase PRIMARY KEY (EmploymentId)
    );
END;
GO

SET NOCOUNT ON;

/* ---------- 1. Sincronizar la foto y restaurar el estado de contratación ---------- */
-- Quitar fotos de contrataciones que ya no existen (la 05 se volvió a correr)
DELETE b
FROM gen.EmploymentBase AS b
WHERE NOT EXISTS (
    SELECT 1 FROM payroll.Employment AS e WHERE e.EmploymentId = b.EmploymentId
);

-- Tomar la foto de las contrataciones nuevas (recién salidas de la 05)
INSERT INTO gen.EmploymentBase (EmploymentId, BaseSalary, BaseUpdatedAt)
SELECT e.EmploymentId, e.MonthlySalary, e.UpdatedAt
FROM payroll.Employment AS e
WHERE NOT EXISTS (
    SELECT 1 FROM gen.EmploymentBase AS b WHERE b.EmploymentId = e.EmploymentId
);

-- Deshacer los aumentos de corridas anteriores
UPDATE e
SET MonthlySalary = b.BaseSalary,
    UpdatedAt     = b.BaseUpdatedAt
FROM payroll.Employment AS e
JOIN gen.EmploymentBase AS b ON b.EmploymentId = e.EmploymentId;

TRUNCATE TABLE payroll.PayrollMovement;

/* ---------- 2. Reglas de aumento anual por país ---------- */
-- Configuración local de esta etapa. Un país sin regla simplemente no
-- recibe aumentos. Argentina con aumentos altos, por inflación.
DROP TABLE IF EXISTS #RaiseRule;
SELECT v.CountryCode, v.Probability, v.MinPct, v.MaxPct
INTO #RaiseRule
FROM (VALUES
    ('MX', 0.80, 0.03, 0.07),
    ('CO', 0.85, 0.05, 0.10),
    ('AR', 0.95, 0.30, 0.60),
    ('PY', 0.75, 0.03, 0.07),
    ('UY', 0.80, 0.05, 0.09)
) AS v (CountryCode, Probability, MinPct, MaxPct);

/* ---------- 3. Contrataciones con su país y frecuencia ---------- */
DROP TABLE IF EXISTS #Emp;
SELECT
    e.EmploymentId,
    d.CountryCode,
    CASE c.PayFrequency WHEN 'BIWEEKLY' THEN 2 ELSE 1 END AS PeriodsPerMonth,
    e.HireDate,
    e.TerminationDate,
    b.BaseSalary
INTO #Emp
FROM payroll.Employment AS e
JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
JOIN payroll.Country AS c ON c.CountryCode = d.CountryCode
JOIN gen.EmploymentBase AS b ON b.EmploymentId = e.EmploymentId;

/* ---------- 4. Historia de sueldos: sueldo de contratación + aumentos ---------- */
-- Evento inicial: el alta, con 0% de aumento
DROP TABLE IF EXISTS #SalaryEvent;
SELECT e.EmploymentId, e.HireDate AS EventDate, CAST(0 AS FLOAT) AS Pct
INTO #SalaryEvent
FROM #Emp AS e;

-- Un posible aumento cada 1 de enero del calendario de periodos,
-- solo si la contratación ya existía y seguía activa ese día
INSERT INTO #SalaryEvent (EmploymentId, EventDate, Pct)
SELECT
    e.EmploymentId,
    y.EventDate,
    rr.MinPct + (rr.MaxPct - rr.MinPct) * RAND(CHECKSUM(NEWID()))
FROM #Emp AS e
JOIN #RaiseRule AS rr ON rr.CountryCode = e.CountryCode
CROSS JOIN (
    SELECT DISTINCT DATEFROMPARTS(YEAR(StartDate), 1, 1) AS EventDate
    FROM payroll.PayrollPeriod
) AS y
WHERE e.HireDate < y.EventDate
  AND (e.TerminationDate IS NULL OR e.TerminationDate >= y.EventDate)
  AND RAND(CHECKSUM(NEWID())) < rr.Probability;

-- La historia como intervalos de vigencia. SQL no tiene PRODUCT(), así que
-- el aumento acumulado se calcula como EXP(SUM(LOG(1 + pct))).
-- Esta tabla es, literalmente, una dimensión SCD tipo 2.
DROP TABLE IF EXISTS #SalaryTimeline;
SELECT
    s.EmploymentId,
    s.EventDate AS ValidFrom,
    ISNULL(
        DATEADD(DAY, -1, LEAD(s.EventDate) OVER (PARTITION BY s.EmploymentId ORDER BY s.EventDate)),
        CAST('9999-12-31' AS DATE)
    ) AS ValidTo,
    CAST(e.BaseSalary * EXP(SUM(LOG(1 + s.Pct)) OVER (
            PARTITION BY s.EmploymentId
            ORDER BY s.EventDate
            ROWS UNBOUNDED PRECEDING))
         AS DECIMAL(18,2)) AS Salary
INTO #SalaryTimeline
FROM #SalaryEvent AS s
JOIN #Emp AS e ON e.EmploymentId = s.EmploymentId;

/* ---------- 5. Contratación x periodo activo, con el sueldo vigente ---------- */
DROP TABLE IF EXISTS #EmpPeriod;
SELECT
    e.EmploymentId,
    e.CountryCode,
    e.PeriodsPerMonth,
    p.PeriodId,
    p.PayDate,
    MONTH(p.StartDate) AS PeriodMonth,
    CASE WHEN p.EndDate = EOMONTH(p.StartDate) THEN 1 ELSE 0 END AS IsLastOfMonth,
    st.Salary
INTO #EmpPeriod
FROM #Emp AS e
JOIN payroll.PayrollPeriod AS p
    ON p.CountryCode = e.CountryCode
   AND p.StartDate <= ISNULL(e.TerminationDate, CAST('9999-12-31' AS DATE))
   AND p.EndDate   >= e.HireDate
JOIN #SalaryTimeline AS st
    ON st.EmploymentId = e.EmploymentId
   -- Si el alta fue a mitad del periodo, el sueldo vigente es el del alta
   AND GREATEST(p.StartDate, e.HireDate) BETWEEN st.ValidFrom AND st.ValidTo;

/* ---------- 6. Reglas de alcance EMPLOYMENT: se deciden una vez por contratación ---------- */
DROP TABLE IF EXISTS #EmpRule;
SELECT
    e.EmploymentId,
    r.RuleId,
    r.MinValue + (r.MaxValue - r.MinValue) * RAND(CHECKSUM(NEWID())) AS RuleValue
INTO #EmpRule
FROM #Emp AS e
JOIN gen.ConceptRule AS r ON r.CountryCode = e.CountryCode
WHERE r.Scope = 'EMPLOYMENT'
  AND RAND(CHECKSUM(NEWID())) < r.Probability;

/* ---------- 7. Primera pasada: todas las reglas excepto PCT_EARNINGS ---------- */
-- La hora de proceso se materializa aquí, una sola vez por fila, para que
-- CreatedAt y UpdatedAt no terminen con dos tiradas distintas de NEWID().
DROP TABLE IF EXISTS #Mov;
SELECT
    ep.EmploymentId,
    ep.PeriodId,
    pc.ConceptId,
    pc.ConceptType,
    CAST(a.Amount AS DECIMAL(18,2)) AS Amount,
    DATEADD(SECOND, 64800 + CAST(RAND(CHECKSUM(NEWID())) * 7200 AS INT),
            CAST(ep.PayDate AS DATETIME2(3))) AS ProcessedAt
INTO #Mov
FROM #EmpPeriod AS ep
JOIN gen.ConceptRule AS r ON r.CountryCode = ep.CountryCode
JOIN payroll.PayrollConcept AS pc
    ON pc.CountryCode = r.CountryCode
   AND pc.Code = r.ConceptCode
LEFT JOIN #EmpRule AS er
    ON er.EmploymentId = ep.EmploymentId
   AND er.RuleId = r.RuleId
CROSS APPLY (
    SELECT CASE
        WHEN r.Scope = 'EMPLOYMENT' THEN er.RuleValue
        ELSE r.MinValue + (r.MaxValue - r.MinValue) * RAND(CHECKSUM(NEWID()))
    END AS RuleValue
) AS v
CROSS APPLY (
    SELECT CASE r.Method
        WHEN 'SALARY'     THEN ep.Salary / ep.PeriodsPerMonth
        WHEN 'PCT_SALARY' THEN ep.Salary * v.RuleValue
                               / CASE WHEN r.PayMonth IS NULL THEN ep.PeriodsPerMonth ELSE 1 END
        WHEN 'FIXED'      THEN v.RuleValue
                               / CASE WHEN r.PayMonth IS NULL THEN ep.PeriodsPerMonth ELSE 1 END
    END AS Amount
) AS a
WHERE r.Method <> 'PCT_EARNINGS'
  AND (r.PayMonth IS NULL OR (r.PayMonth = ep.PeriodMonth AND ep.IsLastOfMonth = 1))
  AND (r.SalaryFrom IS NULL OR ep.Salary >= r.SalaryFrom)
  AND (r.SalaryTo   IS NULL OR ep.Salary <= r.SalaryTo)
  AND (
        (r.Scope = 'EMPLOYMENT' AND er.RuleId IS NOT NULL)
     OR (r.Scope = 'PERIOD' AND RAND(CHECKSUM(NEWID())) < r.Probability)
  );

/* ---------- 8. Segunda pasada: PCT_EARNINGS sobre las percepciones del periodo ---------- */
-- Depende de la primera pasada: el impuesto necesita las percepciones ya calculadas.
INSERT INTO #Mov (EmploymentId, PeriodId, ConceptId, ConceptType, Amount, ProcessedAt)
SELECT
    ern.EmploymentId,
    ern.PeriodId,
    pc.ConceptId,
    pc.ConceptType,
    CAST(ern.Earnings * (r.MinValue + (r.MaxValue - r.MinValue) * RAND(CHECKSUM(NEWID())))
         AS DECIMAL(18,2)),
    DATEADD(SECOND, 64800 + CAST(RAND(CHECKSUM(NEWID())) * 7200 AS INT),
            CAST(ep.PayDate AS DATETIME2(3)))
FROM (
    SELECT EmploymentId, PeriodId, SUM(Amount) AS Earnings
    FROM #Mov
    WHERE ConceptType = 'EARNING'
    GROUP BY EmploymentId, PeriodId
) AS ern
JOIN #EmpPeriod AS ep
    ON ep.EmploymentId = ern.EmploymentId
   AND ep.PeriodId = ern.PeriodId
JOIN gen.ConceptRule AS r
    ON r.CountryCode = ep.CountryCode
   AND r.Method = 'PCT_EARNINGS'
JOIN payroll.PayrollConcept AS pc
    ON pc.CountryCode = r.CountryCode
   AND pc.Code = r.ConceptCode
WHERE (r.SalaryFrom IS NULL OR ep.Salary >= r.SalaryFrom)
  AND (r.SalaryTo   IS NULL OR ep.Salary <= r.SalaryTo)
  AND RAND(CHECKSUM(NEWID())) < r.Probability;

/* ---------- 9. Cargar los movimientos ---------- */
-- TABLOCK sobre una tabla vacía en modelo SIMPLE permite registro mínimo
-- en el log de transacciones: mucho menos disco y mucho menos tiempo.
INSERT INTO payroll.PayrollMovement WITH (TABLOCK)
    (EmploymentId, PeriodId, ConceptId, Amount, CreatedAt, UpdatedAt)
SELECT EmploymentId, PeriodId, ConceptId, Amount, ProcessedAt, ProcessedAt
FROM #Mov;

/* ---------- 10. El origen solo guarda el sueldo vigente ---------- */
-- Se sobrescribe MonthlySalary con el último sueldo: la historia se pierde
-- en el origen, a propósito. En la fase 3 la reconstruirás desde los movimientos.
UPDATE e
SET MonthlySalary = st.Salary,
    UpdatedAt = CASE WHEN r.RaisedAt > e.UpdatedAt THEN r.RaisedAt ELSE e.UpdatedAt END
FROM payroll.Employment AS e
JOIN #SalaryTimeline AS st
    ON st.EmploymentId = e.EmploymentId
   AND st.ValidTo = '9999-12-31'
CROSS APPLY (
    SELECT DATEADD(HOUR, 10, CAST(st.ValidFrom AS DATETIME2(3))) AS RaisedAt
) AS r
WHERE st.ValidFrom > e.HireDate;  -- solo quienes tuvieron al menos un aumento

/* ---------- 11. Resumen ---------- */
SELECT
    (SELECT COUNT(*) FROM #EmpPeriod) AS EmploymentPeriods,
    (SELECT COUNT(*) FROM #SalaryEvent WHERE Pct > 0) AS Raises,
    (SELECT COUNT_BIG(*) FROM payroll.PayrollMovement) AS Movements;
GO
