/*
    04_generate_periods.sql
    Calendario de periodos de nómina por país, según su frecuencia de pago.
    Requisito: haber corrido 02_seed_catalogs.sql.
    Idempotente: inserta solo los periodos que faltan
    (llave natural: CountryCode + StartDate).
*/

USE LabNomina;
GO

DECLARE @From DATE = '2023-01-01';
DECLARE @To   DATE = '2025-12-01';  -- primer día del último mes

WITH Months AS (
    SELECT DATEADD(MONTH, value, @From) AS MonthStart
    FROM GENERATE_SERIES(0, DATEDIFF(MONTH, @From, @To))
)
INSERT INTO payroll.PayrollPeriod (CountryCode, StartDate, EndDate, PayDate)
SELECT c.CountryCode, d.StartDate, d.EndDate, d.EndDate
FROM Months AS m
CROSS JOIN payroll.Country AS c
CROSS JOIN (VALUES (1), (2)) AS h (Half)
CROSS APPLY (
    SELECT
        CASE h.Half
            WHEN 1 THEN m.MonthStart
            ELSE DATEADD(DAY, 15, m.MonthStart)
        END AS StartDate,
        CASE
            WHEN c.PayFrequency = 'BIWEEKLY' AND h.Half = 1
                THEN DATEADD(DAY, 14, m.MonthStart)
            ELSE EOMONTH(m.MonthStart)
        END AS EndDate
) AS d
WHERE (h.Half = 1 OR c.PayFrequency = 'BIWEEKLY')
  AND NOT EXISTS (
      SELECT 1
      FROM payroll.PayrollPeriod AS pp
      WHERE pp.CountryCode = c.CountryCode
        AND pp.StartDate = d.StartDate
  );
GO
