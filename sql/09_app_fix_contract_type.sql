/*
    09_app_fix_contract_type.sql
    SIMULACIÓN: corrección del equipo de la app (APP-882), el miércoles.
    - Normaliza los valores mal capturados ('temporary ').
    - Llena los 2 NULL: RH confirmó que ambas contrataciones son indefinidas.
    - A petición del equipo de datos, TODA corrección actualiza UpdatedAt.
    - Agrega un CHECK para que no vuelva a entrar basura.
    Córrelo una sola vez, como sa, en SSMS (127.0.0.1,1434).
*/

USE LabNomina;
GO

-- 1. Valores con minúsculas o espacios. BIN2 distingue mayúsculas y
--    DATALENGTH distingue los espacios al final: la query de Emma.
UPDATE payroll.Employment
SET ContractType = UPPER(LTRIM(RTRIM(ContractType))),
    UpdatedAt    = SYSUTCDATETIME()
WHERE ContractType COLLATE Latin1_General_BIN2 <> UPPER(LTRIM(RTRIM(ContractType)))
   OR DATALENGTH(ContractType) <> DATALENGTH(LTRIM(RTRIM(ContractType)));
GO

-- 2. Los NULL del endpoint móvil v2
UPDATE payroll.Employment
SET ContractType = 'INDEFINITE',
    UpdatedAt    = SYSUTCDATETIME()
WHERE ContractType IS NULL;
GO

-- 3. La regla en la tabla. Un CHECK con IN a secas NO bastaría: con la
--    collation CI de la base, 'temporary ' IN ('TEMPORARY') es verdadero.
--    Y un CHECK deja pasar los NULL si no se piden explícitamente.
IF OBJECT_ID('payroll.CK_Employment_ContractType', 'C') IS NULL
    ALTER TABLE payroll.Employment WITH CHECK
        ADD CONSTRAINT CK_Employment_ContractType CHECK (
            ContractType IS NOT NULL
            AND ContractType COLLATE Latin1_General_BIN2 IN ('INDEFINITE', 'TEMPORARY')
            AND DATALENGTH(ContractType) = DATALENGTH(RTRIM(ContractType))
        );
GO

-- Validación del equipo de la app (esta vez, sin que la collation esconda nada)
SELECT
    '[' + ContractType COLLATE Latin1_General_BIN2 + ']' AS VisibleValue,
    DATALENGTH(ContractType)                            AS Bytes,
    COUNT(*)                                            AS Employments
FROM payroll.Employment
GROUP BY ContractType COLLATE Latin1_General_BIN2, DATALENGTH(ContractType)
ORDER BY VisibleValue;
