/*
    03_generator_config.sql
    Configuración del generador de datos sintéticos (esquema gen).
    Este esquema NO forma parte del sistema origen: solo existe en el lab
    y nunca se extrae. Por eso sus tablas no llevan CreatedAt/UpdatedAt.
    Requisito: haber corrido 02_seed_catalogs.sql.
    Idempotente: solo inserta lo que falta.

    Convenciones de las reglas:
    - Valores porcentuales como fracción (0.05 = 5%).
    - SALARY: el sueldo mensual; PCT_SALARY: % del sueldo mensual;
      PCT_EARNINGS: % de las percepciones del periodo; FIXED: monto mensual
      en moneda local.
    - Valores recurrentes en base mensual; el generador los prorratea por
      periodo (a la mitad en países quincenales).
    - Reglas con PayMonth: se pagan completas en el último periodo de ese mes.
    - Scope PERIOD: se decide en cada periodo. EMPLOYMENT: se decide una vez
      por contratación (aplica y monto) y se repite en todos sus periodos.
    - SalaryFrom / SalaryTo: la regla solo aplica dentro de ese rango de sueldo.
*/

USE LabNomina;
GO

IF SCHEMA_ID('gen') IS NULL
    EXEC('CREATE SCHEMA gen');
GO

/* ---------- Perfil de cada país ---------- */
IF OBJECT_ID('gen.CountryProfile', 'U') IS NULL
BEGIN
    CREATE TABLE gen.CountryProfile (
        CountryCode    CHAR(2)       NOT NULL,
        EmployeeShare  DECIMAL(5,4)  NOT NULL,
        SalaryMin      DECIMAL(18,2) NOT NULL,
        SalaryMax      DECIMAL(18,2) NOT NULL,
        CONSTRAINT PK_CountryProfile PRIMARY KEY (CountryCode),
        CONSTRAINT FK_CountryProfile_Country FOREIGN KEY (CountryCode) REFERENCES payroll.Country (CountryCode),
        CONSTRAINT CK_CountryProfile_EmployeeShare CHECK (EmployeeShare > 0 AND EmployeeShare <= 1),
        CONSTRAINT CK_CountryProfile_Salary CHECK (SalaryMin > 0 AND SalaryMin <= SalaryMax)
    );
END;
GO

/* ---------- Reglas de generación por concepto ---------- */
IF OBJECT_ID('gen.ConceptRule', 'U') IS NULL
BEGIN
    CREATE TABLE gen.ConceptRule (
        RuleId       INT IDENTITY(1,1) NOT NULL,
        CountryCode  CHAR(2)           NOT NULL,
        ConceptCode  VARCHAR(5)        NOT NULL,
        Method       VARCHAR(20)       NOT NULL,
        Scope        VARCHAR(10)       NOT NULL,
        Probability  DECIMAL(5,4)      NOT NULL,
        MinValue     DECIMAL(18,4)     NOT NULL,
        MaxValue     DECIMAL(18,4)     NOT NULL,
        PayMonth     TINYINT           NULL,
        SalaryFrom   DECIMAL(18,2)     NULL,
        SalaryTo     DECIMAL(18,2)     NULL,
        CONSTRAINT PK_ConceptRule PRIMARY KEY (RuleId),
        CONSTRAINT FK_ConceptRule_PayrollConcept FOREIGN KEY (CountryCode, ConceptCode)
            REFERENCES payroll.PayrollConcept (CountryCode, Code),
        CONSTRAINT UQ_ConceptRule_CountryCode_ConceptCode_PayMonth UNIQUE (CountryCode, ConceptCode, PayMonth),
        CONSTRAINT CK_ConceptRule_Method CHECK (Method IN ('SALARY', 'PCT_SALARY', 'PCT_EARNINGS', 'FIXED')),
        CONSTRAINT CK_ConceptRule_Scope CHECK (Scope IN ('PERIOD', 'EMPLOYMENT')),
        CONSTRAINT CK_ConceptRule_Probability CHECK (Probability > 0 AND Probability <= 1),
        CONSTRAINT CK_ConceptRule_Value CHECK (MinValue >= 0 AND MinValue <= MaxValue),
        CONSTRAINT CK_ConceptRule_PayMonth CHECK (PayMonth BETWEEN 1 AND 12),
        -- Si alguno es NULL, el CHECK pasa: solo valida cuando existen ambos
        CONSTRAINT CK_ConceptRule_SalaryRange CHECK (SalaryFrom <= SalaryTo)
    );
END;
GO

/* ---------- Perfiles: reparto de empleados y rango de sueldo mensual ---------- */
INSERT INTO gen.CountryProfile (CountryCode, EmployeeShare, SalaryMin, SalaryMax)
SELECT v.CountryCode, v.EmployeeShare, v.SalaryMin, v.SalaryMax
FROM (VALUES
    ('MX', 0.40,      10000.00,     80000.00),
    ('CO', 0.25,    1423500.00,  15000000.00),
    ('AR', 0.15,     800000.00,   6000000.00),
    ('PY', 0.10,    2900000.00,  20000000.00),
    ('UY', 0.10,      24000.00,    200000.00)
) AS v (CountryCode, EmployeeShare, SalaryMin, SalaryMax)
WHERE NOT EXISTS (
    SELECT 1 FROM gen.CountryProfile AS p
    WHERE p.CountryCode = v.CountryCode
);
GO

/* ---------- Reglas ---------- */
INSERT INTO gen.ConceptRule
    (CountryCode, ConceptCode, Method, Scope, Probability, MinValue, MaxValue, PayMonth, SalaryFrom, SalaryTo)
SELECT v.CountryCode, v.ConceptCode, v.Method, v.Scope, v.Probability,
       v.MinValue, v.MaxValue, v.PayMonth, v.SalaryFrom, v.SalaryTo
FROM (VALUES
    -- México
    ('MX', 'P001', 'SALARY',       'PERIOD',     1.00, 1.0000, 1.0000, NULL, NULL, NULL),
    ('MX', 'P002', 'PCT_SALARY',   'PERIOD',     0.20, 0.0500, 0.1500, NULL, NULL, NULL),
    ('MX', 'P003', 'PCT_SALARY',   'PERIOD',     0.10, 0.0500, 0.2000, NULL, NULL, NULL),
    ('MX', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 12,   NULL, NULL),
    ('MX', 'P005', 'PCT_SALARY',   'PERIOD',     1.00, 0.3000, 1.0000, 5,    NULL, NULL),
    ('MX', 'D001', 'PCT_EARNINGS', 'PERIOD',     1.00, 0.1200, 0.1200, NULL, NULL, NULL),
    ('MX', 'D002', 'PCT_SALARY',   'PERIOD',     1.00, 0.0250, 0.0250, NULL, NULL, NULL),
    ('MX', 'D003', 'PCT_SALARY',   'EMPLOYMENT', 0.15, 0.0500, 0.1000, NULL, NULL, NULL),
    -- Paraguay
    ('PY', 'P001', 'SALARY',       'PERIOD',     1.00, 1.0000, 1.0000, NULL, NULL, NULL),
    ('PY', 'P002', 'PCT_SALARY',   'PERIOD',     0.20, 0.0500, 0.1500, NULL, NULL, NULL),
    ('PY', 'P003', 'PCT_SALARY',   'PERIOD',     0.10, 0.0500, 0.2000, NULL, NULL, NULL),
    ('PY', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 1.0000, 1.0000, 12,   NULL, NULL),
    ('PY', 'P005', 'FIXED',        'EMPLOYMENT', 0.35, 150000, 450000, NULL, NULL, NULL),
    ('PY', 'D002', 'PCT_SALARY',   'PERIOD',     1.00, 0.0900, 0.0900, NULL, NULL, NULL),
    ('PY', 'D003', 'FIXED',        'EMPLOYMENT', 0.10, 200000, 1000000, NULL, NULL, NULL),
    -- Argentina
    ('AR', 'P001', 'SALARY',       'PERIOD',     1.00, 1.0000, 1.0000, NULL, NULL, NULL),
    ('AR', 'P002', 'PCT_SALARY',   'PERIOD',     0.20, 0.0500, 0.1500, NULL, NULL, NULL),
    ('AR', 'P003', 'PCT_SALARY',   'PERIOD',     0.10, 0.0500, 0.2000, NULL, NULL, NULL),
    ('AR', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 6,    NULL, NULL),
    ('AR', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 12,   NULL, NULL),
    ('AR', 'P005', 'PCT_SALARY',   'PERIOD',     0.85, 0.0833, 0.0833, NULL, NULL, NULL),
    ('AR', 'D001', 'PCT_EARNINGS', 'PERIOD',     1.00, 0.1000, 0.1000, NULL, 3000000, NULL),
    ('AR', 'D002', 'PCT_SALARY',   'PERIOD',     1.00, 0.1100, 0.1100, NULL, NULL, NULL),
    ('AR', 'D003', 'PCT_SALARY',   'EMPLOYMENT', 0.60, 0.0200, 0.0200, NULL, NULL, NULL),
    ('AR', 'D004', 'PCT_SALARY',   'PERIOD',     1.00, 0.0300, 0.0300, NULL, NULL, NULL),
    ('AR', 'D005', 'PCT_SALARY',   'PERIOD',     1.00, 0.0300, 0.0300, NULL, NULL, NULL),
    -- Colombia
    ('CO', 'P001', 'SALARY',       'PERIOD',     1.00, 1.0000, 1.0000, NULL, NULL, NULL),
    ('CO', 'P002', 'PCT_SALARY',   'PERIOD',     0.25, 0.0500, 0.1500, NULL, NULL, NULL),
    ('CO', 'P003', 'PCT_SALARY',   'PERIOD',     0.10, 0.0500, 0.2000, NULL, NULL, NULL),
    ('CO', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 6,    NULL, NULL),
    ('CO', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 12,   NULL, NULL),
    ('CO', 'P005', 'FIXED',        'PERIOD',     1.00, 200000, 200000, NULL, NULL, 2847000),
    ('CO', 'D001', 'PCT_EARNINGS', 'PERIOD',     1.00, 0.0500, 0.0500, NULL, 5000000, NULL),
    ('CO', 'D002', 'PCT_SALARY',   'PERIOD',     1.00, 0.0400, 0.0400, NULL, NULL, NULL),
    ('CO', 'D003', 'FIXED',        'EMPLOYMENT', 0.15, 150000, 800000, NULL, NULL, NULL),
    ('CO', 'D004', 'PCT_SALARY',   'PERIOD',     1.00, 0.0400, 0.0400, NULL, NULL, NULL),
    -- Uruguay
    ('UY', 'P001', 'SALARY',       'PERIOD',     1.00, 1.0000, 1.0000, NULL, NULL, NULL),
    ('UY', 'P002', 'PCT_SALARY',   'PERIOD',     0.20, 0.0500, 0.1500, NULL, NULL, NULL),
    ('UY', 'P003', 'PCT_SALARY',   'PERIOD',     0.10, 0.0500, 0.2000, NULL, NULL, NULL),
    ('UY', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 6,    NULL, NULL),
    ('UY', 'P004', 'PCT_SALARY',   'PERIOD',     1.00, 0.5000, 0.5000, 12,   NULL, NULL),
    ('UY', 'P005', 'PCT_SALARY',   'PERIOD',     0.70, 0.6500, 0.6500, 1,    NULL, NULL),
    ('UY', 'D001', 'PCT_EARNINGS', 'PERIOD',     1.00, 0.1000, 0.1000, NULL, 46000, NULL),
    ('UY', 'D002', 'PCT_SALARY',   'PERIOD',     1.00, 0.1500, 0.1500, NULL, NULL, NULL),
    ('UY', 'D003', 'FIXED',        'EMPLOYMENT', 0.10, 2000,   10000,  NULL, NULL, NULL),
    ('UY', 'D004', 'PCT_SALARY',   'PERIOD',     1.00, 0.0450, 0.0450, NULL, NULL, NULL)
) AS v (CountryCode, ConceptCode, Method, Scope, Probability, MinValue, MaxValue, PayMonth, SalaryFrom, SalaryTo)
WHERE NOT EXISTS (
    SELECT 1 FROM gen.ConceptRule AS r
    WHERE r.CountryCode = v.CountryCode
      AND r.ConceptCode = v.ConceptCode
      AND ISNULL(r.PayMonth, 0) = ISNULL(v.PayMonth, 0)
);
GO
