/*
    06_movement_tests.sql
    Pruebas de datos de la etapa 06 (historia de sueldos y movimientos).
    Convención: cada prueba PASA si regresa CERO filas.

    Hay dos huecos marcados con TU TURNO.
    Ojo: estas pruebas recorren millones de filas. Si alguna tarda
    bastante, anota cuánto: es material para la fase 2 (índices).
*/

USE LabNomina;
GO

/* ------------------------------------------------------------------
   Prueba 1: cada contratación tiene exactamente UN sueldo base (P001)
   en cada periodo en que estuvo activa. Atrapa tanto periodos sin
   sueldo (0) como sueldos duplicados (2 o más).
------------------------------------------------------------------ */
WITH Expected AS (
    SELECT e.EmploymentId, p.PeriodId
    FROM payroll.Employment AS e
    JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
    JOIN payroll.PayrollPeriod AS p
        ON p.CountryCode = d.CountryCode
       AND p.StartDate <= ISNULL(e.TerminationDate, CAST('9999-12-31' AS DATE))
       AND p.EndDate   >= e.HireDate
),
SalaryMov AS (
    SELECT m.EmploymentId, m.PeriodId, COUNT(*) AS Cnt
    FROM payroll.PayrollMovement AS m
    JOIN payroll.PayrollConcept AS pc ON pc.ConceptId = m.ConceptId
    WHERE pc.Code = 'P001'
    GROUP BY m.EmploymentId, m.PeriodId
)
SELECT ex.EmploymentId, ex.PeriodId, ISNULL(sm.Cnt, 0) AS Cnt
FROM Expected AS ex
LEFT JOIN SalaryMov AS sm
    ON sm.EmploymentId = ex.EmploymentId
   AND sm.PeriodId = ex.PeriodId
WHERE ISNULL(sm.Cnt, 0) <> 1;
GO

/* ------------------------------------------------------------------
   Prueba 2: ningún movimiento cae fuera de su contratación.
   Es la prueba que vigila la imperfección deliberada del esquema:
   nada en la base impide un movimiento en un periodo de otro país.
------------------------------------------------------------------ */
SELECT m.MovementId, m.EmploymentId, m.PeriodId, d.CountryCode, p.CountryCode AS PeriodCountry
FROM payroll.PayrollMovement AS m
JOIN payroll.Employment AS e ON e.EmploymentId = m.EmploymentId
JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
JOIN payroll.PayrollPeriod AS p ON p.PeriodId = m.PeriodId
WHERE p.CountryCode <> d.CountryCode
   OR (
       /* TU TURNO: el periodo NO se traslapa con las fechas de la contratación.
          Hay dos formas de no traslaparse: el periodo terminó antes del alta,
          o empezó después de la baja (recuerda que la baja puede ser nula). */
   );
GO

/* ------------------------------------------------------------------
   Prueba 3: los conceptos con mes fijo (aguinaldos, primas, PTU...)
   solo aparecen en alguno de sus meses de pago.
   Patrón EXISTS / NOT EXISTS: "es un concepto con mes fijo" Y
   "no existe una regla que lo permita en este mes".
------------------------------------------------------------------ */
SELECT m.MovementId, pc.CountryCode, pc.Code, p.StartDate
FROM payroll.PayrollMovement AS m
JOIN payroll.PayrollConcept AS pc ON pc.ConceptId = m.ConceptId
JOIN payroll.PayrollPeriod AS p ON p.PeriodId = m.PeriodId
WHERE EXISTS (
          SELECT 1 FROM gen.ConceptRule AS r
          WHERE r.CountryCode = pc.CountryCode
            AND r.ConceptCode = pc.Code
            AND r.PayMonth IS NOT NULL
      )
  AND NOT EXISTS (
          SELECT 1 FROM gen.ConceptRule AS r
          WHERE r.CountryCode = pc.CountryCode
            AND r.ConceptCode = pc.Code
            AND r.PayMonth = MONTH(p.StartDate)
      );
GO

/* ------------------------------------------------------------------
   Prueba 4: la historia se puede reconstruir.
   En las contrataciones activas, el último sueldo base pagado
   (P001 x periodos por mes) debe coincidir con el MonthlySalary que
   quedó en el origen. Tolerancia de 5 centavos por el redondeo de las
   quincenas. Si esta prueba pasa, los movimientos guardan la historia
   que el origen sobrescribió: es lo que usarás en la fase 3.
------------------------------------------------------------------ */
WITH LastSalaryMov AS (
    SELECT
        m.EmploymentId,
        m.Amount,
        ROW_NUMBER() OVER (PARTITION BY m.EmploymentId ORDER BY p.StartDate DESC) AS rn
    FROM payroll.PayrollMovement AS m
    JOIN payroll.PayrollConcept AS pc ON pc.ConceptId = m.ConceptId
    JOIN payroll.PayrollPeriod AS p ON p.PeriodId = m.PeriodId
    WHERE pc.Code = 'P001'
)
SELECT
    e.EmploymentId,
    e.MonthlySalary,
    l.Amount * CASE c.PayFrequency WHEN 'BIWEEKLY' THEN 2 ELSE 1 END AS LastPaidMonthly
FROM payroll.Employment AS e
JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
JOIN payroll.Country AS c ON c.CountryCode = d.CountryCode
JOIN LastSalaryMov AS l
    ON l.EmploymentId = e.EmploymentId
   AND l.rn = 1
WHERE e.TerminationDate IS NULL
  AND ABS(l.Amount * CASE c.PayFrequency WHEN 'BIWEEKLY' THEN 2 ELSE 1 END - e.MonthlySalary) > 0.05;
GO

/* ------------------------------------------------------------------
   Prueba 5: prueba de volumen. El total de movimientos debe quedar
   entre 4 y 6 millones. En producción, este tipo de prueba detecta
   cargas incompletas o duplicadas aunque cada fila se vea bien.
------------------------------------------------------------------ */
SELECT COUNT_BIG(*) AS TotalMovements
FROM payroll.PayrollMovement
/* TU TURNO: que la consulta regrese su fila SOLO si el total queda
   fuera del rango. Pista: sin GROUP BY, toda la tabla es un solo grupo,
   y hay una cláusula que filtra grupos. */;
GO
