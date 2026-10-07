-- 01_silver.sql
-- Capa silver: la versión más reciente de cada fila, leída directo de bronze.
--
-- Son VISTAS: no copian datos y siempre reflejan lo último que hay en bronze.
-- El patrón de cada una:
--   1. read_parquet lee todas las cargas publicadas (load_id=*). Las carpetas
--      _inprogress_ no coinciden con el patrón, así que nunca se leen.
--   2. hive_partitioning convierte la carpeta load_id=... en una columna.
--   3. QUALIFY filtra sobre una función de ventana (lo que en SQL Server
--      requeriría un CTE): por cada llave primaria, se queda con la fila de
--      UpdatedAt más reciente. Si hay empate, gana la carga más nueva.
--
-- Las rutas son relativas: corre siempre desde la raíz del repo.

CREATE SCHEMA IF NOT EXISTS silver;

CREATE OR REPLACE VIEW silver.country AS
SELECT * FROM read_parquet('data/bronze/payroll/country/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY CountryCode ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.department AS
SELECT * FROM read_parquet('data/bronze/payroll/department/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY DepartmentId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.employee AS
SELECT * FROM read_parquet('data/bronze/payroll/employee/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY EmployeeId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.employment AS
SELECT * FROM read_parquet('data/bronze/payroll/employment/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY EmploymentId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.payroll_concept AS
SELECT * FROM read_parquet('data/bronze/payroll/payroll_concept/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY ConceptId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.payroll_period AS
SELECT * FROM read_parquet('data/bronze/payroll/payroll_period/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY PeriodId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.payroll_movement AS
SELECT * FROM read_parquet('data/bronze/payroll/payroll_movement/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY MovementId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.settlement AS
SELECT * FROM read_parquet('data/bronze/payroll/settlement/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY SettlementId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

CREATE OR REPLACE VIEW silver.settlement_line AS
SELECT * FROM read_parquet('data/bronze/payroll/settlement_line/load_id=*/*.parquet', hive_partitioning = true)
QUALIFY ROW_NUMBER() OVER (PARTITION BY SettlementLineId ORDER BY UpdatedAt DESC, load_id DESC) = 1;

-- Verificación: filas en bronze (todas las versiones) contra silver (solo la última)
SELECT 'country' AS table_name,
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/country/load_id=*/*.parquet')) AS bronze_rows,
       (SELECT COUNT(*) FROM silver.country) AS silver_rows
UNION ALL SELECT 'department',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/department/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.department)
UNION ALL SELECT 'employee',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/employee/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.employee)
UNION ALL SELECT 'employment',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/employment/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.employment)
UNION ALL SELECT 'payroll_concept',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/payroll_concept/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.payroll_concept)
UNION ALL SELECT 'payroll_period',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/payroll_period/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.payroll_period)
UNION ALL SELECT 'payroll_movement',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/payroll_movement/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.payroll_movement)
UNION ALL SELECT 'settlement',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/settlement/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.settlement)
UNION ALL SELECT 'settlement_line',
       (SELECT COUNT(*) FROM read_parquet('data/bronze/payroll/settlement_line/load_id=*/*.parquet')),
       (SELECT COUNT(*) FROM silver.settlement_line);
