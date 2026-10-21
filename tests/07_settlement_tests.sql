/*
    07_settlement_tests.sql
    Pruebas de datos de la etapa 07 (finiquitos).
    Convención: cada prueba PASA si regresa CERO filas.

    Hay dos huecos marcados con TU TURNO.
*/

USE LabNomina;
GO

/* ------------------------------------------------------------------
   Prueba 1: toda contratación terminada tiene exactamente un finiquito,
   y ninguna activa tiene uno.

   Ojo con COUNT: con LEFT JOIN, COUNT(*) cuenta 1 aunque no haya
   finiquito (cuenta la fila de la contratación). COUNT(s.SettlementId)
   solo cuenta valores no nulos, así que da 0 cuando no hay finiquito.
------------------------------------------------------------------ */
SELECT
    e.EmploymentId,
    e.TerminationDate,
    COUNT(s.SettlementId) AS Settlements
FROM payroll.Employment AS e
LEFT JOIN payroll.Settlement AS s ON s.EmploymentId = e.EmploymentId
GROUP BY e.EmploymentId, e.TerminationDate
HAVING
    /* TU TURNO: dos casos de violación unidos con OR.
       1) Terminada con un número de finiquitos distinto de 1.
       2) Activa con al menos un finiquito. */
;
GO

/* ------------------------------------------------------------------
   Prueba 2: el finiquito se fecha entre el día de la baja y 15 días después.
------------------------------------------------------------------ */
SELECT s.SettlementId, e.TerminationDate, s.SettlementDate
FROM payroll.Settlement AS s
JOIN payroll.Employment AS e ON e.EmploymentId = s.EmploymentId
WHERE s.SettlementDate < e.TerminationDate
   OR s.SettlementDate > DATEADD(DAY, 15, e.TerminationDate);
GO

/* ------------------------------------------------------------------
   Prueba 3: composición de cada finiquito.
   Siempre una línea de vacaciones (F002) y una de seguridad social (D002);
   indemnización (F001) solo en despidos.

   Técnica: agregación condicional, SUM(CASE ...). Convierte filas en
   columnas en una sola pasada: un "pivote" escrito a mano.
------------------------------------------------------------------ */
WITH Composition AS (
    SELECT
        s.SettlementId,
        e.TerminationReason,
        SUM(CASE WHEN pc.Code = 'F001' THEN 1 ELSE 0 END) AS F001,
        SUM(CASE WHEN pc.Code = 'F002' THEN 1 ELSE 0 END) AS F002,
        SUM(CASE WHEN pc.Code = 'D002' THEN 1 ELSE 0 END) AS D002
    FROM payroll.Settlement AS s
    JOIN payroll.Employment AS e ON e.EmploymentId = s.EmploymentId
    LEFT JOIN payroll.SettlementLine AS sl ON sl.SettlementId = s.SettlementId
    LEFT JOIN payroll.PayrollConcept AS pc ON pc.ConceptId = sl.ConceptId
    GROUP BY s.SettlementId, e.TerminationReason
)
SELECT *
FROM Composition
WHERE F002 <> 1
   OR D002 <> 1
   OR (
       /* TU TURNO: la indemnización aparece donde no debe, o falta donde sí.
          Piensa en los dos lados: despidos sin exactamente una F001,
          y no despidos con alguna F001. */

   );
GO

/* ------------------------------------------------------------------
   Prueba 4: estatus y auditoría coherentes.
   Borrador solo para bajas de los últimos 30 días de la ventana, y nunca
   una modificación anterior a la creación.
------------------------------------------------------------------ */
SELECT s.SettlementId, s.Status, e.TerminationDate, s.CreatedAt, s.UpdatedAt
FROM payroll.Settlement AS s
JOIN payroll.Employment AS e ON e.EmploymentId = s.EmploymentId
WHERE s.UpdatedAt < s.CreatedAt
   OR (s.Status =  'DRAFT' AND e.TerminationDate <= DATEADD(DAY, -30, CAST('2025-12-31' AS DATE)))
   OR (s.Status <> 'DRAFT' AND e.TerminationDate >  DATEADD(DAY, -30, CAST('2025-12-31' AS DATE)));
GO

/* ------------------------------------------------------------------
   Prueba 5: la indemnización equivale a entre 1 y 12 sueldos.
   Si esta prueba falla después de re-correr la 06 sin re-correr la 07,
   no es un bug: es la dependencia del DAG avisándote que la 07 quedó
   con sueldos viejos.
------------------------------------------------------------------ */
SELECT
    s.SettlementId,
    sl.Amount,
    e.MonthlySalary,
    sl.Amount / e.MonthlySalary AS SalaryMonths
FROM payroll.SettlementLine AS sl
JOIN payroll.PayrollConcept AS pc ON pc.ConceptId = sl.ConceptId
JOIN payroll.Settlement AS s ON s.SettlementId = sl.SettlementId
JOIN payroll.Employment AS e ON e.EmploymentId = s.EmploymentId
WHERE pc.Code = 'F001'
  AND sl.Amount / e.MonthlySalary NOT BETWEEN 0.999 AND 12.001;
GO
