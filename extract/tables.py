"""
tables.py
Contratos de esquema: qué tablas se extraen del origen y con qué tipos
EXACTOS deben aterrizar en bronze. Si un dato no cabe en su contrato,
la extracción falla ruidosamente en lugar de transformarlo en silencio.
"""

from dataclasses import dataclass

import pyarrow as pa

# --- Tipos reutilizables ---------------------------------------------------
MONEY = pa.decimal128(18, 2)      # igual que DECIMAL(18,2): el dinero nunca en double
TIMESTAMP = pa.timestamp("ms")    # DATETIME2(3) tiene precisión de milisegundos
DATE = pa.date32()
INT = pa.int32()                  # INT de SQL Server = 32 bits
BIGINT = pa.int64()
TEXT = pa.string()


def required(name: str, type_: pa.DataType) -> pa.Field:
    """Columna NOT NULL en el origen."""
    return pa.field(name, type_, nullable=False)


def optional(name: str, type_: pa.DataType) -> pa.Field:
    """Columna que acepta nulos en el origen."""
    return pa.field(name, type_, nullable=True)


# Las columnas de auditoría que llevan todas las tablas
AUDIT = [required("CreatedAt", TIMESTAMP), required("UpdatedAt", TIMESTAMP)]


@dataclass(frozen=True)
class TableContract:
    """Una dataclass es una clase que solo guarda datos, sin escribir constructor."""
    source: str                    # tabla en SQL Server, con su esquema
    folder: str                    # carpeta de destino en bronze
    schema: pa.Schema              # columnas, tipos y nulabilidad declarados
    watermark: str = "UpdatedAt"   # columna para la extracción incremental


# El * de "*AUDIT" desempaca esa lista dentro de la lista de columnas.
TABLES = [
    TableContract("payroll.Country", "country", pa.schema([
        required("CountryCode", TEXT),
        required("Name", TEXT),
        required("CurrencyCode", TEXT),
        required("PayFrequency", TEXT),
        *AUDIT,
    ])),
    TableContract("payroll.Department", "department", pa.schema([
        required("DepartmentId", INT),
        required("CountryCode", TEXT),
        required("Name", TEXT),
        *AUDIT,
    ])),
    TableContract("payroll.Employee", "employee", pa.schema([
        required("EmployeeId", INT),
        required("FirstName", TEXT),
        required("LastName", TEXT),
        optional("BirthDate", DATE),
        *AUDIT,
    ])),
    TableContract("payroll.Employment", "employment", pa.schema([
        required("EmploymentId", INT),
        required("EmployeeId", INT),
        required("DepartmentId", INT),
        required("JobTitle", TEXT),
        required("MonthlySalary", MONEY),
        required("HireDate", DATE),
        optional("TerminationDate", DATE),
        optional("TerminationReason", TEXT),
        *AUDIT,
    ])),
    TableContract("payroll.PayrollConcept", "payroll_concept", pa.schema([
        required("ConceptId", INT),
        required("CountryCode", TEXT),
        required("Code", TEXT),
        required("Name", TEXT),
        required("ConceptType", TEXT),
        *AUDIT,
    ])),
    TableContract("payroll.PayrollPeriod", "payroll_period", pa.schema([
        required("PeriodId", INT),
        required("CountryCode", TEXT),
        required("StartDate", DATE),
        required("EndDate", DATE),
        required("PayDate", DATE),
        *AUDIT,
    ])),
    TableContract("payroll.PayrollMovement", "payroll_movement", pa.schema([
        required("MovementId", BIGINT),
        required("EmploymentId", INT),
        required("PeriodId", INT),
        required("ConceptId", INT),
        required("Amount", MONEY),
        *AUDIT,
    ])),
    TableContract("payroll.Settlement", "settlement", pa.schema([
        required("SettlementId", INT),
        required("EmploymentId", INT),
        required("SettlementDate", DATE),
        required("Status", TEXT),
        *AUDIT,
    ])),
    TableContract("payroll.SettlementLine", "settlement_line", pa.schema([
        required("SettlementLineId", BIGINT),
        required("SettlementId", INT),
        required("ConceptId", INT),
        required("Amount", MONEY),
        *AUDIT,
    ])),
]
