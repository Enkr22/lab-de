/*
    08_app_contract_type.sql
    SIMULACIÓN: este cambio NO lo hace el equipo de datos. Es el release 4.12
    de la app de RH, que el equipo de la app ya desplegó en la base de origen.
    Córrelo una sola vez, como sa, en SSMS (127.0.0.1,1434).
*/

USE LabNomina;
GO

-- Release 4.12: tipo de contrato en la contratación.
-- Las contrataciones existentes nacen como INDEFINITE.
IF COL_LENGTH('payroll.Employment', 'ContractType') IS NULL
BEGIN
    ALTER TABLE payroll.Employment
        ADD ContractType VARCHAR(20) NULL
            CONSTRAINT DF_Employment_ContractType DEFAULT ('INDEFINITE') WITH VALUES;
END;
GO

-- Ajuste de datos solicitado por RH: marcar como temporales las contrataciones
-- que terminaron por fin de contrato y las temporales que siguen vigentes.
UPDATE payroll.Employment
SET ContractType = 'TEMPORARY'
WHERE TerminationReason = 'END_OF_CONTRACT'
   OR (TerminationDate IS NULL AND EmploymentId % 20 = 0);
GO

-- Primeras capturas hechas desde la app con el release nuevo:
-- una carga masiva de sucursal y dos altas desde el endpoint móvil.
UPDATE payroll.Employment
SET ContractType = 'temporary ',
    UpdatedAt    = SYSUTCDATETIME()
WHERE EmploymentId IN (
    SELECT TOP (31) EmploymentId
    FROM payroll.Employment
    WHERE TerminationDate IS NULL AND EmploymentId % 20 = 1
    ORDER BY EmploymentId DESC
);

UPDATE payroll.Employment
SET ContractType = NULL,
    UpdatedAt    = SYSUTCDATETIME()
WHERE EmploymentId IN (
    SELECT TOP (2) EmploymentId
    FROM payroll.Employment
    WHERE TerminationDate IS NULL AND EmploymentId % 20 = 2
    ORDER BY EmploymentId DESC
);
GO

-- Validación del equipo de la app
SELECT ContractType, COUNT(*) AS Employments
FROM payroll.Employment
GROUP BY ContractType
ORDER BY Employments DESC;
