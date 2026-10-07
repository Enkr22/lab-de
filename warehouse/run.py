"""
run.py
Ejecuta un archivo .sql contra el warehouse local de DuckDB y muestra
el resultado de la última consulta del archivo.

Uso, desde la raíz del repo y con el entorno virtual activo:
    python warehouse/run.py warehouse/sql/01_silver.sql
"""

import sys
import time
from pathlib import Path
import duckdb

DATABASE = Path("data") / "warehouse.duckdb"


def main() -> None:
    sql_file = Path(sys.argv[1])
    sql = sql_file.read_text(encoding="utf-8")

    DATABASE.parent.mkdir(parents=True, exist_ok=True)

    # DuckDB corre dentro de este proceso: no hay servidor que levantar,
    # la base completa es un solo archivo (data/warehouse.duckdb).
    con = duckdb.connect(str(DATABASE))
    try:
        start = time.perf_counter()
        con.execute(sql)  # ejecuta todas las sentencias del archivo, en orden
        elapsed = time.perf_counter() - start

        # Si la última sentencia fue un SELECT, mostramos su resultado
        if con.description:
            print(con.fetchdf().to_string(index=False))
    finally:
        con.close()

    print(f"\n{sql_file.name}: {elapsed:.2f} s")


if __name__ == "__main__":
    main()
