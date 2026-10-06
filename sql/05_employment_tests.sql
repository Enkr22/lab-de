/*
    05_employment_tests.sql
    Pruebas de datos de la etapa 05 (empleados y contrataciones).
    Convención (la misma de dbt): cada prueba PASA si regresa CERO filas.

    Actualizado para la etapa 06: los aumentos de sueldo ahora sobrescriben
    MonthlySalary y UpdatedAt, así que las pruebas 3 y 5 cambiaron de regla.
    Las pruebas documentan la regla vigente, no una verdad eterna.
    La prueba 3 requiere haber corrido la 06 al menos una vez.
*/

USE LabNomina;
GO

/* Prueba 1: el reparto por país no se desvía más de 2 puntos de su EmployeeShare */
WITH Actual AS (
    SELECT
        d.CountryCode,
        COUNT(DISTINCT e.EmployeeId) * 1.0
            / SUM(COUNT(DISTINCT e.EmployeeId)) OVER () AS ActualShare
    FROM payroll.Employment AS e
    JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
    GROUP BY d.CountryCode
)
SELECT a.CountryCode, a.ActualShare, p.EmployeeShare
FROM Actual AS a
JOIN gen.CountryProfile AS p ON p.CountryCode = a.CountryCode
WHERE ABS(a.ActualShare - p.EmployeeShare) > 0.02;
GO

/* Prueba 2: cada recontratación empieza después de la baja de la anterior.
   El filtro de afuera garantiza que SÍ hay contratación anterior; dentro de
   ese contexto, PrevTerminationDate nulo solo puede significar "sigue activa". */
WITH Ordered AS (
    SELECT
        e.EmployeeId,
        e.EmploymentId,
        e.HireDate,
        LAG(e.EmploymentId)    OVER (PARTITION BY e.EmployeeId ORDER BY e.HireDate) AS PrevEmploymentId,
        LAG(e.TerminationDate) OVER (PARTITION BY e.EmployeeId ORDER BY e.HireDate) AS PrevTerminationDate
    FROM payroll.Employment AS e
)
SELECT *
FROM Ordered
WHERE PrevEmploymentId IS NOT NULL
  AND (PrevTerminationDate IS NULL OR HireDate <= PrevTerminationDate);
GO

/* Prueba 3: el sueldo DE CONTRATACIÓN está dentro del rango de su país.
   Regla nueva: después de la 06, el sueldo vigente puede superar el máximo
   por los aumentos, así que se valida el sueldo con que se contrató. */
SELECT
    e.EmploymentId,
    d.CountryCode,
    COALESCE(b.BaseSalary, e.MonthlySalary) AS HireSalary,
    p.SalaryMin,
    p.SalaryMax
FROM payroll.Employment AS e
JOIN payroll.Department AS d ON d.DepartmentId = e.DepartmentId
JOIN gen.CountryProfile AS p ON p.CountryCode = d.CountryCode
LEFT JOIN gen.EmploymentBase AS b ON b.EmploymentId = e.EmploymentId
WHERE COALESCE(b.BaseSalary, e.MonthlySalary) NOT BETWEEN p.SalaryMin AND p.SalaryMax;
GO

/* Prueba 4a: edad exacta en la primera contratación entre 18 y 55 */
WITH FirstHire AS (
    SELECT EmployeeId, MIN(HireDate) AS HireDate
    FROM payroll.Employment
    GROUP BY EmployeeId
),
Ages AS (
    SELECT
        emp.EmployeeId,
        emp.BirthDate,
        fh.HireDate,
        DATEDIFF(YEAR, emp.BirthDate, fh.HireDate)
            - CASE
                  WHEN DATEADD(YEAR, DATEDIFF(YEAR, emp.BirthDate, fh.HireDate), emp.BirthDate) > fh.HireDate
                      THEN 1
                  ELSE 0
              END AS AgeAtHire
    FROM payroll.Employee AS emp
    JOIN FirstHire AS fh ON fh.EmployeeId = emp.EmployeeId
    WHERE emp.BirthDate IS NOT NULL
)
SELECT *
FROM Ages
WHERE AgeAtHire NOT BETWEEN 18 AND 55;
GO

/* Prueba 4b: los nulos de BirthDate rondan el 3% (entre 2% y 4%) */
SELECT s.NullShare
FROM (
    SELECT AVG(CASE WHEN BirthDate IS NULL THEN 1.0 ELSE 0.0 END) AS NullShare
    FROM payroll.Employee
) AS s
WHERE s.NullShare NOT BETWEEN 0.02 AND 0.04;
GO

/* Prueba 5: auditoría coherente.
   Regla nueva: ya no se exige UpdatedAt = CreatedAt en las activas, porque
   un aumento es una modificación legítima del registro. */
SELECT
    e.EmploymentId,
    e.CreatedAt,
    e.UpdatedAt,
    e.TerminationDate
FROM payroll.Employment AS e
WHERE e.UpdatedAt < e.CreatedAt
   OR (e.TerminationDate IS NOT NULL AND e.TerminationDate <> CAST(e.UpdatedAt AS DATE));
GO
