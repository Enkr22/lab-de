"""
export_for_bi.py
Capa de servicio: exporta los marts de dbt a archivos Parquet que Power BI
(o cualquier herramienta de BI) puede leer sin tocar la base de dbt.

Por qué un archivo y no conectar Power BI directo a DuckDB:
  - DuckDB permite un solo proceso escribiendo el archivo. Si Power BI lo
    tuviera abierto, bloquearía a dbt en la corrida de las 2:00 a. m.
  - Las herramientas de BI tienen sistemas de tipos más estrechos. Este export
    es un contrato: HUGEINT -> BIGINT y decimales de más de 18 dígitos ->
    DECIMAL(18, s). Si un valor no cabe, el cast truena: falla ruidosamente.

Uso, desde la raíz del repo:
    python serving/export_for_bi.py
"""

import os
import re
import time
from pathlib import Path

import duckdb

DATABASE = Path("data") / "dbt.duckdb"
OUTPUT = Path("data") / "serving"
TABLES = [
    "dim_date",
    "dim_country",
    "dim_concept",
    "dim_employee",
    "fct_payroll_movement",
    "fct_settlement",
    "fct_absence_day",
]


def bi_safe_select(con, table: str) -> str:
    """Arma un SELECT que convierte cada columna a un tipo que BI entiende."""
    columns = con.execute(f"DESCRIBE marts.{table}").fetchall()
    parts = []
    for name, col_type, *_ in columns:
        decimal = re.fullmatch(r"DECIMAL\((\d+),(\d+)\)", col_type)
        if col_type == "HUGEINT":
            parts.append(f'CAST("{name}" AS BIGINT) AS "{name}"')
        elif decimal and int(decimal.group(1)) > 18:
            parts.append(f'CAST("{name}" AS DECIMAL(18,{decimal.group(2)})) AS "{name}"')
        else:
            parts.append(f'"{name}"')
    return f"SELECT {', '.join(parts)} FROM marts.{table}"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Solo lectura: el export nunca modifica la base de dbt
    con = duckdb.connect(str(DATABASE), read_only=True)
    try:
        print(f"{'Tabla':<24}{'Filas':>12}{'MB':>8}{'Segundos':>10}")
        for table in TABLES:
            start = time.perf_counter()
            final = OUTPUT / f"{table}.parquet"
            tmp = OUTPUT / f"_{table}.parquet.tmp"

            # Mismo patrón de publicación atómica del extractor: se escribe a un
            # temporal y se renombra al final. Power BI nunca lee un archivo a medias.
            con.execute(
                f"COPY ({bi_safe_select(con, table)}) "
                f"TO '{tmp.as_posix()}' (FORMAT parquet, COMPRESSION zstd)"
            )
            os.replace(tmp, final)

            rows = con.execute(f"SELECT COUNT(*) FROM marts.{table}").fetchone()[0]
            size_mb = final.stat().st_size / 1024 / 1024
            print(f"{table:<24}{rows:>12,}{size_mb:>8.1f}{time.perf_counter() - start:>10.1f}")
    finally:
        con.close()


if __name__ == "__main__":
    main()
