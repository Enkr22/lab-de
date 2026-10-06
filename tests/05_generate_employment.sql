/*
    05_generate_employment.sql
    Genera empleados y contrataciones, con bajas y recontrataciones.
    Requisito: 03_generator_config.sql y 04_generate_periods.sql.

    Estrategia: full refresh. Borra todo lo generado de esta etapa en
    adelante (finiquitos, movimientos, contrataciones y empleados) y lo
    vuelve a generar. Cada corrida produce el mismo volumen, pero datos
    distintos, porque es aleatorio.
*/

USE LabNomina;
GO

SET NOCOUNT ON;

/* ---------- Parámetros ---------- */
DECLARE @EmployeeCount    INT   = 30000;
DECLARE @HistoryStart     DATE  = '2015-01-01';  -- alta más antigua posible
DECLARE @WindowStart      DATE  = '2023-01-01';  -- inicio de la ventana de nómina
DECLARE @WindowEnd        DATE  = '2025-12-31';  -- fin de la ventana de nómina
DECLARE @InitialShare     FLOAT = 0.60;          -- ya contratados antes de la ventana
DECLARE @TerminationRate  FLOAT = 0.35;          -- contrataciones que terminan en la ventana
DECLARE @RehireRate       FLOAT = 0.10;          -- bajas que se recontratan
DECLARE @BirthNullRate    FLOAT = 0.03;          -- empleados sin fecha de nacimiento

/* ---------- 1. Full refresh: vaciar de las hojas hacia la raíz ---------- */
TRUNCATE TABLE payroll.SettlementLine;   -- hoja: ninguna FK la referencia
DELETE FROM payroll.Settlement;          -- referenciada por SettlementLine
TRUNCATE TABLE payroll.PayrollMovement;  -- hoja
DELETE FROM payroll.Employment;          -- referenciada por PayrollMovement y Settlement
DELETE FROM payroll.Employee;            -- referenciada por Employment

/* ---------- 2. Listas para nombres y puestos ---------- */
DROP TABLE IF EXISTS #FirstName;
SELECT ROW_NUMBER() OVER (ORDER BY v.Name) AS n, v.Name
INTO #FirstName
FROM (VALUES
    (N'José'), (N'María'), (N'Juan'), (N'Ana'), (N'Luis'),
    (N'Carmen'), (N'Carlos'), (N'Laura'), (N'Miguel'), (N'Sofía'),
    (N'Jorge'), (N'Valentina'), (N'Diego'), (N'Camila'), (N'Andrés'),
    (N'Lucía'), (N'Fernando'), (N'Daniela'), (N'Ricardo'), (N'Gabriela')
) AS v (Name);

DROP TABLE IF EXISTS #LastName;
SELECT ROW_NUMBER() OVER (ORDER BY v.Name) AS n, v.Name
INTO #LastName
FROM (VALUES
    (N'García'), (N'Rodríguez'), (N'Martínez'), (N'López'), (N'González'),
    (N'Pérez'), (N'Sánchez'), (N'Ramírez'), (N'Torres'), (N'Flores'),
    (N'Rivera'), (N'Gómez'), (N'Díaz'), (N'Morales'), (N'Herrera'),
    (N'Castro'), (N'Vargas'), (N'Romero'), (N'Suárez'), (N'Benítez')
) AS v (Name);

DROP TABLE IF EXISTS #JobTitle;
SELECT ROW_NUMBER() OVER (ORDER BY v.Title) AS n, v.Title
INTO #JobTitle
FROM (VALUES
    (N'Auxiliar'), (N'Asistente'), (N'Técnico'), (N'Analista'),
    (N'Especialista'), (N'Coordinador'), (N'Supervisor'), (N'Gerente')
) AS v (Title);

DECLARE @FirstNameCount INT = (SELECT COUNT(*) FROM #FirstName);
DECLARE @LastNameCount  INT = (SELECT COUNT(*) FROM #LastName);
DECLARE @JobTitleCount  INT = (SELECT COUNT(*) FROM #JobTitle);

/* ---------- 3. Rangos acumulados por país y departamentos numerados ---------- */
-- Cada país ocupa un tramo de [0, 1) proporcional a su EmployeeShare.
-- Un número aleatorio cae en un tramo, y ese es su país.
DROP TABLE IF EXISTS #CountryRange;
SELECT
    p.CountryCode,
    p.SalaryMin,
    p.SalaryMax,
    SUM(p.EmployeeShare) OVER (ORDER BY p.CountryCode ROWS UNBOUNDED PRECEDING) - p.EmployeeShare AS RangeFrom,
    SUM(p.EmployeeShare) OVER (ORDER BY p.CountryCode ROWS UNBOUNDED PRECEDING) AS RangeTo
INTO #CountryRange
FROM gen.CountryProfile AS p;

DROP TABLE IF EXISTS #Dept;
SELECT
    d.DepartmentId,
    d.CountryCode,
    ROW_NUMBER() OVER (PARTITION BY d.CountryCode ORDER BY d.DepartmentId) AS n,
    COUNT(*) OVER (PARTITION BY d.CountryCode) AS DeptCount
INTO #Dept
FROM payroll.Department AS d;

/* ---------- 4. Tirar los dados una sola vez y guardarlos ---------- */
-- Se materializan en una tabla temporal a propósito: si NEWID() viviera
-- en un CTE, el motor podría reevaluarlo en cada referencia y darte
-- valores distintos para la "misma" tirada.
DROP TABLE IF EXISTS #Draw;
SELECT
    s.value AS n,
    RAND(CHECKSUM(NEWID())) AS rCountry,
    RAND(CHECKSUM(NEWID())) AS rDept,
    RAND(CHECKSUM(NEWID())) AS rFirst,
    RAND(CHECKSUM(NEWID())) AS rLast,
    RAND(CHECKSUM(NEWID())) AS rTitle,
    RAND(CHECKSUM(NEWID())) AS rSalary,
    RAND(CHECKSUM(NEWID())) AS rInitial,
    RAND(CHECKSUM(NEWID())) AS rHire,
    RAND(CHECKSUM(NEWID())) AS rAge,
    RAND(CHECKSUM(NEWID())) AS rBirthNull,
    RAND(CHECKSUM(NEWID())) AS rTerm,
    RAND(CHECKSUM(NEWID())) AS rTermDate,
    RAND(CHECKSUM(NEWID())) AS rReason,
    RAND(CHECKSUM(NEWID())) AS rTime,
    RAND(CHECKSUM(NEWID())) AS rRehire,
    RAND(CHECKSUM(NEWID())) AS rRehireGap,
    RAND(CHECKSUM(NEWID())) AS rRehireDept,
    RAND(CHECKSUM(NEWID())) AS rRaise
INTO #Draw
FROM GENERATE_SERIES(1, @EmployeeCount) AS s;

/* ---------- 5. Armar la primera contratación de cada empleado ---------- */
DROP TABLE IF EXISTS #Emp;
SELECT
    ROW_NUMBER() OVER (ORDER BY dr.n) AS Seq,
    cr.CountryCode,
    fn.Name AS FirstName,
    ln.Name AS LastName,
    CASE
        WHEN dr.rBirthNull < @BirthNullRate THEN NULL
        -- 18 años exactos antes del alta, menos hasta 37 años adicionales en días
        ELSE DATEADD(DAY, -CAST(dr.rAge * 37 * 365.25 AS INT), DATEADD(YEAR, -18, h.HireDate))
    END AS BirthDate,
    dp.DepartmentId,
    jt.Title AS JobTitle,
    -- Elevar al cuadrado sesga hacia sueldos bajos: pocos ganan mucho
    CAST(cr.SalaryMin + (cr.SalaryMax - cr.SalaryMin) * SQUARE(dr.rSalary) AS DECIMAL(18,2)) AS MonthlySalary,
    h.HireDate,
    t.TerminationDate,
    CASE
        WHEN t.TerminationDate IS NULL THEN NULL
        WHEN dr.rReason < 0.55 THEN 'RESIGNATION'
        WHEN dr.rReason < 0.85 THEN 'DISMISSAL'
        ELSE 'END_OF_CONTRACT'
    END AS TerminationReason,
    -- Auditoría con fechas de negocio y hora hábil (09:00 a 18:00)
    DATEADD(SECOND, 32400 + CAST(dr.rTime * 32400 AS INT),
            CAST(h.HireDate AS DATETIME2(3))) AS CreatedAt,
    DATEADD(SECOND, 32400 + CAST(dr.rTime * 32400 AS INT),
            CAST(COALESCE(t.TerminationDate, h.HireDate) AS DATETIME2(3))) AS UpdatedAt,
    dr.rTime,
    dr.rRehire,
    dr.rRehireGap,
    dr.rRehireDept,
    dr.rRaise
INTO #Emp
FROM #Draw AS dr
JOIN #CountryRange AS cr
    ON dr.rCountry >= cr.RangeFrom
   AND dr.rCountry <  cr.RangeTo
JOIN #FirstName AS fn ON fn.n = 1 + CAST(dr.rFirst * @FirstNameCount AS INT)
JOIN #LastName  AS ln ON ln.n = 1 + CAST(dr.rLast  * @LastNameCount  AS INT)
JOIN #JobTitle  AS jt ON jt.n = 1 + CAST(dr.rTitle * @JobTitleCount  AS INT)
JOIN #Dept AS dp
    ON dp.CountryCode = cr.CountryCode
   AND dp.n = 1 + CAST(dr.rDept * dp.DeptCount AS INT)
CROSS APPLY (
    SELECT CASE
        WHEN dr.rInitial < @InitialShare
            THEN DATEADD(DAY, CAST(dr.rHire * DATEDIFF(DAY, @HistoryStart, @WindowStart) AS INT), @HistoryStart)
        ELSE DATEADD(DAY, CAST(dr.rHire * (DATEDIFF(DAY, @WindowStart, @WindowEnd) + 1) AS INT), @WindowStart)
    END AS HireDate
) AS h
CROSS APPLY (
    -- Una baja ocurre dentro de la ventana y al menos 30 días después del alta
    SELECT CASE
        WHEN DATEADD(DAY, 30, h.HireDate) > @WindowStart THEN DATEADD(DAY, 30, h.HireDate)
        ELSE @WindowStart
    END AS TermFrom
) AS tf
CROSS APPLY (
    SELECT CASE
        WHEN dr.rTerm < @TerminationRate AND tf.TermFrom <= @WindowEnd
            THEN DATEADD(DAY, CAST(dr.rTermDate * (DATEDIFF(DAY, tf.TermFrom, @WindowEnd) + 1) AS INT), tf.TermFrom)
    END AS TerminationDate
) AS t;

/* ---------- 6. Insertar empleados y recuperar sus IDs ---------- */
-- Con ORDER BY, SQL Server garantiza que los IDENTITY se asignan en ese
-- orden. Como la tabla se vació al inicio, el N-ésimo EmployeeId
-- corresponde al Seq N.
INSERT INTO payroll.Employee (FirstName, LastName, BirthDate, CreatedAt, UpdatedAt)
SELECT FirstName, LastName, BirthDate, CreatedAt, CreatedAt
FROM #Emp
ORDER BY Seq;

DROP TABLE IF EXISTS #EmpMap;
SELECT EmployeeId, ROW_NUMBER() OVER (ORDER BY EmployeeId) AS Seq
INTO #EmpMap
FROM payroll.Employee;

INSERT INTO payroll.Employment
    (EmployeeId, DepartmentId, JobTitle, MonthlySalary, HireDate,
     TerminationDate, TerminationReason, CreatedAt, UpdatedAt)
SELECT
    m.EmployeeId, e.DepartmentId, e.JobTitle, e.MonthlySalary, e.HireDate,
    e.TerminationDate, e.TerminationReason, e.CreatedAt, e.UpdatedAt
FROM #Emp AS e
JOIN #EmpMap AS m ON m.Seq = e.Seq;

/* ---------- 7. Recontrataciones: mismo empleado, nueva contratación ---------- */
-- Entre 30 y 365 días después de la baja, en un departamento del mismo país,
-- con un aumento de hasta 10% (topado al máximo del país). Quedan activas.
INSERT INTO payroll.Employment
    (EmployeeId, DepartmentId, JobTitle, MonthlySalary, HireDate,
     TerminationDate, TerminationReason, CreatedAt, UpdatedAt)
SELECT
    m.EmployeeId,
    dp.DepartmentId,
    e.JobTitle,
    CAST(LEAST(e.MonthlySalary * (1 + e.rRaise * 0.10), cr.SalaryMax) AS DECIMAL(18,2)),
    r.RehireDate,
    NULL,
    NULL,
    r.RehireAt,
    r.RehireAt
FROM #Emp AS e
JOIN #EmpMap AS m ON m.Seq = e.Seq
JOIN #CountryRange AS cr ON cr.CountryCode = e.CountryCode
JOIN #Dept AS dp
    ON dp.CountryCode = e.CountryCode
   AND dp.n = 1 + CAST(e.rRehireDept * dp.DeptCount AS INT)
CROSS APPLY (
    SELECT DATEADD(DAY, 30 + CAST(e.rRehireGap * 336 AS INT), e.TerminationDate) AS RehireDate
) AS rd
CROSS APPLY (
    SELECT rd.RehireDate AS RehireDate,
           DATEADD(SECOND, 32400 + CAST(e.rTime * 32400 AS INT),
                   CAST(rd.RehireDate AS DATETIME2(3))) AS RehireAt
) AS r
WHERE e.TerminationDate IS NOT NULL
  AND e.rRehire < @RehireRate
  AND r.RehireDate <= @WindowEnd;

/* ---------- 8. Resumen ---------- */
SELECT
    (SELECT COUNT(*) FROM payroll.Employee) AS Employees,
    (SELECT COUNT(*) FROM payroll.Employment) AS Employments,
    (SELECT COUNT(*) FROM payroll.Employment WHERE TerminationDate IS NOT NULL) AS Terminated,
    (SELECT COUNT(*) - COUNT(DISTINCT EmployeeId) FROM payroll.Employment) AS Rehires;
GO
