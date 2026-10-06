/*
    02_seed_catalogs.sql
    Catálogos del sistema origen: países, departamentos y conceptos.
    Requisito: haber corrido 01_create_schema.sql.
    Idempotente: solo inserta lo que falta (no borra ni actualiza).
*/

USE LabNomina;
GO

/* ---------- Países ---------- */
INSERT INTO payroll.Country (CountryCode, Name, CurrencyCode, PayFrequency)
SELECT v.CountryCode, v.Name, v.CurrencyCode, v.PayFrequency
FROM (VALUES
    ('MX', N'México',    'MXN', 'BIWEEKLY'),
    ('PY', N'Paraguay',  'PYG', 'MONTHLY'),
    ('AR', N'Argentina', 'ARS', 'MONTHLY'),
    ('CO', N'Colombia',  'COP', 'BIWEEKLY'),
    ('UY', N'Uruguay',   'UYU', 'MONTHLY')
) AS v (CountryCode, Name, CurrencyCode, PayFrequency)
WHERE NOT EXISTS (
    SELECT 1 FROM payroll.Country AS c
    WHERE c.CountryCode = v.CountryCode
);
GO

/* ---------- Departamentos: cada país x cada nombre ---------- */
INSERT INTO payroll.Department (CountryCode, Name)
SELECT c.CountryCode, d.Name
FROM payroll.Country AS c
CROSS JOIN (VALUES
    (N'Finanzas'), (N'Recursos Humanos'), (N'Operaciones'),
    (N'Ventas'), (N'Tecnología')
) AS d (Name)
WHERE NOT EXISTS (
    SELECT 1 FROM payroll.Department AS x
    WHERE x.CountryCode = c.CountryCode
      AND x.Name = d.Name
);
GO

/* ---------- Conceptos de nómina ---------- */
INSERT INTO payroll.PayrollConcept (CountryCode, Code, Name, ConceptType)
SELECT v.CountryCode, v.Code, v.Name, v.ConceptType
FROM (VALUES
    -- México
    ('MX', 'P001', N'Sueldo',                   'EARNING'),
    ('MX', 'P002', N'Tiempo extra',             'EARNING'),
    ('MX', 'P003', N'Bono de productividad',    'EARNING'),
    ('MX', 'P004', N'Aguinaldo',                'EARNING'),
    ('MX', 'P005', N'PTU',                      'EARNING'),
    ('MX', 'D001', N'ISR',                      'DEDUCTION'),
    ('MX', 'D002', N'Cuota obrera IMSS',        'DEDUCTION'),
    ('MX', 'D003', N'Crédito INFONAVIT',        'DEDUCTION'),
    -- Paraguay (sin D001: el IRP no se retiene en nómina)
    ('PY', 'P001', N'Salario',                  'EARNING'),
    ('PY', 'P002', N'Horas extras',             'EARNING'),
    ('PY', 'P003', N'Comisiones',               'EARNING'),
    ('PY', 'P004', N'Aguinaldo',                'EARNING'),
    ('PY', 'P005', N'Bonificación familiar',    'EARNING'),
    ('PY', 'D002', N'Aporte IPS',               'DEDUCTION'),
    ('PY', 'D003', N'Préstamo',                 'DEDUCTION'),
    -- Argentina
    ('AR', 'P001', N'Sueldo básico',            'EARNING'),
    ('AR', 'P002', N'Horas extras',             'EARNING'),
    ('AR', 'P003', N'Comisiones',               'EARNING'),
    ('AR', 'P004', N'SAC',                      'EARNING'),
    ('AR', 'P005', N'Presentismo',              'EARNING'),
    ('AR', 'D001', N'Impuesto a las Ganancias', 'DEDUCTION'),
    ('AR', 'D002', N'Jubilación',               'DEDUCTION'),
    ('AR', 'D003', N'Cuota sindical',           'DEDUCTION'),
    ('AR', 'D004', N'Obra social',              'DEDUCTION'),
    ('AR', 'D005', N'Ley 19.032',               'DEDUCTION'),
    -- Colombia
    ('CO', 'P001', N'Salario',                  'EARNING'),
    ('CO', 'P002', N'Horas extras y recargos',  'EARNING'),
    ('CO', 'P003', N'Comisiones',               'EARNING'),
    ('CO', 'P004', N'Prima de servicios',       'EARNING'),
    ('CO', 'P005', N'Auxilio de transporte',    'EARNING'),
    ('CO', 'D001', N'Retención en la fuente',   'DEDUCTION'),
    ('CO', 'D002', N'Salud',                    'DEDUCTION'),
    ('CO', 'D003', N'Libranza',                 'DEDUCTION'),
    ('CO', 'D004', N'Pensión',                  'DEDUCTION'),
    -- Uruguay
    ('UY', 'P001', N'Sueldo',                   'EARNING'),
    ('UY', 'P002', N'Horas extras',             'EARNING'),
    ('UY', 'P003', N'Comisiones',               'EARNING'),
    ('UY', 'P004', N'Aguinaldo',                'EARNING'),
    ('UY', 'P005', N'Salario vacacional',       'EARNING'),
    ('UY', 'D001', N'IRPF',                     'DEDUCTION'),
    ('UY', 'D002', N'Aporte jubilatorio',       'DEDUCTION'),
    ('UY', 'D003', N'Préstamo',                 'DEDUCTION'),
    ('UY', 'D004', N'FONASA',                   'DEDUCTION')
) AS v (CountryCode, Code, Name, ConceptType)
WHERE NOT EXISTS (
    SELECT 1 FROM payroll.PayrollConcept AS pc
    WHERE pc.CountryCode = v.CountryCode
      AND pc.Code = v.Code
);
GO

/* ---------- Conceptos de finiquito: genéricos para todos los países ---------- */
-- Se agregaron para la etapa 07. Idempotente: si ya existen, no hace nada.
INSERT INTO payroll.PayrollConcept (CountryCode, Code, Name, ConceptType)
SELECT c.CountryCode, v.Code, v.Name, v.ConceptType
FROM payroll.Country AS c
CROSS JOIN (VALUES
    ('F001', N'Indemnización por despido', 'EARNING'),
    ('F002', N'Vacaciones proporcionales', 'EARNING')
) AS v (Code, Name, ConceptType)
WHERE NOT EXISTS (
    SELECT 1 FROM payroll.PayrollConcept AS pc
    WHERE pc.CountryCode = c.CountryCode
      AND pc.Code = v.Code
);
GO
