/*
    07_generate_settlements.sql
    Genera los finiquitos de las contrataciones terminadas.
    Requisito: 06_generate_movements.sql (usa el sueldo final de cada
    contratación) y los conceptos F001/F002 de 02_seed_catalogs.sql.

    Estrategia: full refresh. Si vuelves a correr la 06, vuelve a correr
    la 07: los aumentos cambian, y con ellos el sueldo del finiquito.

    Reglas genéricas e ilustrativas (no son la ley de ningún país):
    - F002 Vacaciones proporcionales: medio sueldo por año, proporcional al
      tiempo desde el último aniversario. En todos los finiquitos.
    - F001 Indemnización: un sueldo por año completo de antigüedad,
      mínimo 1 y máximo 12. Solo en despidos.
    - D002 Seguridad social: la tasa del país aplicada a las vacaciones.
*/

USE LabNomina;
GO

SET NOCOUNT ON;

/* ---------- Parámetros ---------- */
DECLARE @WindowEnd        DATE          = '2025-12-31';
DECLARE @MaxPaymentDelay  INT           = 15;     -- días máximos entre la baja y el finiquito
DECLARE @DraftWindowDays  INT           = 30;     -- bajas recientes: finiquito aún en borrador
DECLARE @CancelRate       FLOAT         = 0.03;   -- finiquitos cancelados
DECLARE @VacationFactor   DECIMAL(5,4)  = 0.5;    -- sueldos de vacaciones por año
DECLARE @IndemnityCap     INT           = 12;     -- tope de sueldos de indemnización

/* ---------- 0. Fallar ruidosamente si falta el catálogo ---------- */
-- Sin esta validación, el JOIN final descartaría en silencio las líneas
-- de conceptos inexistentes, y tendrías finiquitos incompletos sin ningún error.
IF EXISTS (
    SELECT 1
    FROM payroll.Country AS c
    CROSS JOIN (VALUES ('F001'), ('F002'), ('D002')) AS v (Code)
    WHERE NOT EXISTS (
        SELECT 1 FROM payroll.PayrollConcept AS pc
        WHERE pc.CountryCode = c.CountryCode AND pc.Code = v.Code
    )
)
    THROW 50001, 'Faltan conceptos de finiquito (F001/F002/D002). Corre primero el 02_seed_catalogs.sql actualizado.', 1;

/* ---------- 1. Full refresh ---------- */
TRUNCATE TABLE payroll.SettlementLine;   -- hoja
DELETE FROM payroll.Settlement;          -- referenciada por SettlementLine

/* ---------- 2. Contrataciones terminadas, con sus tiradas ---------- */
-- Las tiradas incluyen EmploymentId en su CHECKSUM (la regla de oro de la 06)
DROP TABLE IF EXISTS #Term;
SELECT
    e.EmploymentId,
    d.CountryCode,
    e.HireDate,
    e.TerminationDate,
    e.TerminationReason,
    e.MonthlySalary,
    RAND(CHECKSUM(NEWID(), e.EmploymentId)) AS rDelay,
    RAND(CHECKSUM(NEWID(), e.EmploymentId)) AS rStatus,
    RAND(CHECKSUM(NEWID(), e.EmploymentId)) AS rTime
INTO #Term
FROM payroll.Employment AS e
JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
WHERE e.TerminationDate IS NOT NULL;

/* ---------- 3. Fechas, estatus y antigüedad ---------- */
DROP TABLE IF EXISTS #Calc;
SELECT
    t.EmploymentId,
    t.CountryCode,
    t.TerminationReason,
    t.MonthlySalary,
    sd.SettlementDate,
    st.Status,
    y.FullYears,
    DATEDIFF(DAY, DATEADD(YEAR, y.FullYears, t.HireDate), t.TerminationDate) AS DaysSinceAnniversary,
    ts.CreatedAt,
    CASE
        WHEN st.Status = 'DRAFT' THEN ts.CreatedAt
        -- Pagado o cancelado: el registro cambió de estatus el día del finiquito
        ELSE DATEADD(DAY, DATEDIFF(DAY, t.TerminationDate, sd.SettlementDate), ts.CreatedAt)
    END AS UpdatedAt
INTO #Calc
FROM #Term AS t
CROSS APPLY (
    SELECT DATEADD(DAY, CAST(t.rDelay * (@MaxPaymentDelay + 1) AS INT), t.TerminationDate) AS SettlementDate
) AS sd
CROSS APPLY (
    SELECT CASE
        WHEN t.TerminationDate > DATEADD(DAY, -@DraftWindowDays, @WindowEnd) THEN 'DRAFT'
        WHEN t.rStatus < @CancelRate THEN 'CANCELLED'
        ELSE 'PAID'
    END AS Status
) AS st
CROSS APPLY (
    -- Años cumplidos exactos (el mismo patrón de la prueba de edad)
    SELECT DATEDIFF(YEAR, t.HireDate, t.TerminationDate)
         - CASE
               WHEN DATEADD(YEAR, DATEDIFF(YEAR, t.HireDate, t.TerminationDate), t.HireDate) > t.TerminationDate
                   THEN 1
               ELSE 0
           END AS FullYears
) AS y
CROSS APPLY (
    SELECT DATEADD(SECOND, 32400 + CAST(t.rTime * 32400 AS INT),
                   CAST(t.TerminationDate AS DATETIME2(3))) AS CreatedAt
) AS ts;

/* ---------- 4. Encabezados ---------- */
INSERT INTO payroll.Settlement (EmploymentId, SettlementDate, Status, CreatedAt, UpdatedAt)
SELECT EmploymentId, SettlementDate, Status, CreatedAt, UpdatedAt
FROM #Calc;

/* ---------- 5. Líneas ---------- */
-- El UQ de Settlement.EmploymentId hace trivial encontrar el SettlementId
-- de cada contratación: es una relación uno a uno garantizada por la base.
DROP TABLE IF EXISTS #Line;

-- F002: vacaciones proporcionales, en todos los finiquitos
SELECT
    s.SettlementId,
    c.CountryCode,
    CAST('F002' AS VARCHAR(5)) AS Code,
    CAST(c.MonthlySalary * @VacationFactor * c.DaysSinceAnniversary / 365.0 AS DECIMAL(18,2)) AS Amount,
    c.CreatedAt,
    c.UpdatedAt
INTO #Line
FROM #Calc AS c
JOIN payroll.Settlement AS s ON s.EmploymentId = c.EmploymentId;

-- F001: indemnización, solo despidos
INSERT INTO #Line (SettlementId, CountryCode, Code, Amount, CreatedAt, UpdatedAt)
SELECT
    s.SettlementId,
    c.CountryCode,
    'F001',
    CAST(c.MonthlySalary * LEAST(GREATEST(c.FullYears, 1), @IndemnityCap) AS DECIMAL(18,2)),
    c.CreatedAt,
    c.UpdatedAt
FROM #Calc AS c
JOIN payroll.Settlement AS s ON s.EmploymentId = c.EmploymentId
WHERE c.TerminationReason = 'DISMISSAL';

-- D002: seguridad social del país, aplicada a las vacaciones
INSERT INTO #Line (SettlementId, CountryCode, Code, Amount, CreatedAt, UpdatedAt)
SELECT
    l.SettlementId,
    l.CountryCode,
    'D002',
    CAST(l.Amount * r.MinValue AS DECIMAL(18,2)),
    l.CreatedAt,
    l.UpdatedAt
FROM #Line AS l
JOIN gen.ConceptRule AS r
    ON r.CountryCode = l.CountryCode
   AND r.ConceptCode = 'D002'
WHERE l.Code = 'F002';

INSERT INTO payroll.SettlementLine (SettlementId, ConceptId, Amount, CreatedAt, UpdatedAt)
SELECT l.SettlementId, pc.ConceptId, l.Amount, l.CreatedAt, l.UpdatedAt
FROM #Line AS l
JOIN payroll.PayrollConcept AS pc
    ON pc.CountryCode = l.CountryCode
   AND pc.Code = l.Code;

/* ---------- 6. Resumen ---------- */
SELECT
    (SELECT COUNT(*) FROM payroll.Settlement) AS Settlements,
    (SELECT COUNT(*) FROM payroll.Settlement WHERE Status = 'PAID') AS Paid,
    (SELECT COUNT(*) FROM payroll.Settlement WHERE Status = 'DRAFT') AS Draft,
    (SELECT COUNT(*) FROM payroll.Settlement WHERE Status = 'CANCELLED') AS Cancelled,
    (SELECT COUNT(*) FROM payroll.SettlementLine) AS Lines;
GO
