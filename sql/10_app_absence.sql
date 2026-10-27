/*
    10_app_absence.sql
    SIMULACIÓN: release 4.13 de la app de RH. Nueva tabla de incidencias
    (vacaciones, incapacidades y faltas injustificadas), con la carga
    histórica 2023–2025. Lo despliega el equipo de la app; el equipo de
    datos solo la consume.

    Requisito: 05 a 09.
    Córrelo como sa en SSMS (127.0.0.1,1434).
    Idempotente: vacía la tabla y la vuelve a generar. Los números exactos
    cambian en cada corrida porque es aleatorio.

    Ojo: Absence tiene una llave foránea hacia Employment. Si algún día
    vuelves a correr 05 (que borra contrataciones), primero vacía esta tabla:
    TRUNCATE TABLE payroll.Absence;
*/

USE LabNomina;
GO

IF OBJECT_ID('payroll.Absence', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.Absence (
        AbsenceId     INT IDENTITY(1,1) NOT NULL,
        EmploymentId  INT               NOT NULL,
        AbsenceType   VARCHAR(20)       NOT NULL,
        StartDate     DATE              NOT NULL,
        EndDate       DATE              NOT NULL,   -- inclusiva: el último día de ausencia
        Status        VARCHAR(20)       NOT NULL CONSTRAINT DF_Absence_Status    DEFAULT ('APPROVED'),
        CreatedAt     DATETIME2(3)      NOT NULL CONSTRAINT DF_Absence_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt     DATETIME2(3)      NOT NULL CONSTRAINT DF_Absence_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Absence PRIMARY KEY (AbsenceId),
        CONSTRAINT FK_Absence_Employment FOREIGN KEY (EmploymentId) REFERENCES payroll.Employment (EmploymentId),
        CONSTRAINT CK_Absence_Type   CHECK (AbsenceType IN ('VACATION', 'SICK_LEAVE', 'UNJUSTIFIED')),
        CONSTRAINT CK_Absence_Status CHECK (Status IN ('APPROVED', 'CANCELLED')),
        CONSTRAINT CK_Absence_Dates  CHECK (EndDate >= StartDate)
    );
END;
GO

TRUNCATE TABLE payroll.Absence;
GO

-- 1. Ventana activa de cada contratación dentro de 2023–2025
DROP TABLE IF EXISTS #Active;

SELECT
    e.EmploymentId,
    GREATEST(e.HireDate, CAST('2023-01-01' AS DATE))                                      AS ActiveStart,
    LEAST(COALESCE(e.TerminationDate, CAST('2025-12-31' AS DATE)), CAST('2025-12-31' AS DATE)) AS ActiveEnd
INTO #Active
FROM payroll.Employment AS e;

DELETE FROM #Active WHERE ActiveStart > ActiveEnd;

-- 2. Candidatos: contratación x año x regla. Los números aleatorios se
--    MATERIALIZAN en una tabla temporal: si se calcularan en una expresión
--    usada dos veces, SQL Server podría evaluarlos dos veces con valores
--    distintos. Y van correlacionados con columnas (la lección del 06).
DROP TABLE IF EXISTS #Candidate;

SELECT
    a.EmploymentId,
    a.ActiveStart,
    a.ActiveEnd,
    y.Yr,
    r.AbsenceType,
    r.Slot,
    r.Probability,
    r.MinDays,
    r.MaxDays,
    RAND(CHECKSUM(NEWID(), a.EmploymentId, y.Yr, r.Slot, 0)) AS ProbabilityDraw,
    RAND(CHECKSUM(NEWID(), a.EmploymentId, y.Yr, r.Slot, 1)) AS PositionDraw,
    RAND(CHECKSUM(NEWID(), a.EmploymentId, y.Yr, r.Slot, 2)) AS LengthDraw
INTO #Candidate
FROM #Active AS a
CROSS JOIN (VALUES (2023), (2024), (2025)) AS y (Yr)
CROSS JOIN (VALUES
    ('VACATION',    1, 0.85, 3, 10),
    ('VACATION',    2, 0.50, 2,  6),
    ('SICK_LEAVE',  1, 0.30, 1,  7),
    ('SICK_LEAVE',  2, 0.10, 3, 15),
    ('UNJUSTIFIED', 1, 0.20, 1,  1),
    ('UNJUSTIFIED', 2, 0.08, 1,  1)
) AS r (AbsenceType, Slot, Probability, MinDays, MaxDays)
WHERE DATEFROMPARTS(y.Yr, 12, 31) >= a.ActiveStart
  AND DATEFROMPARTS(y.Yr, 1, 1)   <= a.ActiveEnd;

-- 3. Las incidencias. Empiezan dentro del año, pero pueden terminar en el
--    mes o el año siguiente, siempre dentro de la contratación.
WITH Picked AS (
    SELECT
        c.EmploymentId,
        c.AbsenceType,
        c.ActiveEnd,
        c.PositionDraw,
        GREATEST(c.ActiveStart, DATEFROMPARTS(c.Yr, 1, 1))              AS YearStart,
        LEAST(c.ActiveEnd, DATEFROMPARTS(c.Yr, 12, 31))                 AS YearEnd,
        c.MinDays + CAST(c.LengthDraw * (c.MaxDays - c.MinDays + 1) AS INT) AS Days
    FROM #Candidate AS c
    WHERE c.ProbabilityDraw < c.Probability
)
INSERT INTO payroll.Absence WITH (TABLOCK) (EmploymentId, AbsenceType, StartDate, EndDate)
SELECT
    p.EmploymentId,
    p.AbsenceType,
    s.StartDate,
    LEAST(DATEADD(DAY, p.Days - 1, s.StartDate), p.ActiveEnd) AS EndDate
FROM Picked AS p
CROSS APPLY (
    SELECT DATEADD(DAY, CAST(p.PositionDraw * (DATEDIFF(DAY, p.YearStart, p.YearEnd) + 1) AS INT), p.YearStart) AS StartDate
) AS s;
GO

-- 4. Vacaciones que el empleado canceló después de solicitarlas
UPDATE payroll.Absence
SET Status    = 'CANCELLED',
    UpdatedAt = SYSUTCDATETIME()
WHERE AbsenceType = 'VACATION'
  AND ABS(CHECKSUM(NEWID(), AbsenceId)) % 100 < 6;
GO

-- 5. Bug conocido del endpoint móvil: faltas capturadas después de la baja
INSERT INTO payroll.Absence (EmploymentId, AbsenceType, StartDate, EndDate)
SELECT TOP (12)
    e.EmploymentId,
    'UNJUSTIFIED',
    DATEADD(DAY, 3, e.TerminationDate),
    DATEADD(DAY, 3, e.TerminationDate)
FROM payroll.Employment AS e
WHERE e.TerminationDate BETWEEN '2024-01-01' AND '2025-11-30'
ORDER BY e.EmploymentId;
GO

DROP TABLE IF EXISTS #Candidate;
DROP TABLE IF EXISTS #Active;
GO

-- Validación del equipo de la app
SELECT
    AbsenceType,
    Status,
    COUNT(*)                                   AS Absences,
    SUM(DATEDIFF(DAY, StartDate, EndDate) + 1) AS CalendarDays
FROM payroll.Absence
GROUP BY AbsenceType, Status
ORDER BY AbsenceType, Status;
