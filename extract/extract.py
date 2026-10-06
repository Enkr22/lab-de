"""
extract.py
Extractor incremental: SQL Server -> Parquet en la capa bronze.

Cómo funciona, por cada tabla:
  1. Lee el último watermark guardado: la marca de "hasta dónde ya extraje".
  2. Congela el límite superior: el MAX(UpdatedAt) de este momento.
  3. Extrae solo las filas con UpdatedAt entre ambos, por lotes.
  4. Escribe los lotes en una carpeta temporal y, al terminar, la publica
     renombrándola: ningún lector ve jamás una carga a medias.
  5. Solo entonces avanza el watermark.

Uso, desde la raíz del repo y con el entorno virtual activo:
    python extract/extract.py          # incremental
    python extract/extract.py --full   # ignora los watermarks y extrae todo
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

from tables import TABLES, TableContract

CHUNK_SIZE = 500_000                           # filas por lote: acota la memoria
BRONZE = Path("data") / "bronze" / "payroll"
STATE_FILE = Path("data") / "_state" / "watermarks.json"
EPOCH = "1900-01-01T00:00:00.000"              # watermark inicial: "nunca he extraído"


def get_engine():
    """Conexión con el usuario de solo lectura."""
    load_dotenv()
    url = URL.create(
        "mssql+pyodbc",
        username=os.environ["EXTRACT_USER"],
        password=os.environ["EXTRACT_PASSWORD"],
        host="127.0.0.1",
        port=1434,
        database="LabNomina",
        query={
            "driver": "ODBC Driver 18 for SQL Server",
            "TrustServerCertificate": "yes",
        },
    )
    return create_engine(url)


def load_watermarks() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    return {}


def save_watermarks(watermarks: dict) -> None:
    """Escribe a un temporal y luego lo reemplaza: el archivo nunca queda a medias."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(watermarks, indent=2), encoding="utf-8")
    tmp.replace(STATE_FILE)


def to_arrow(df: pd.DataFrame, contract: TableContract) -> pa.Table:
    """Aplica el contrato: primero la nulabilidad, luego los tipos."""
    for field in contract.schema:
        if not field.nullable and df[field.name].isna().any():
            raise ValueError(
                f"{contract.source}.{field.name} trae nulos y el contrato dice NOT NULL"
            )
    # Si algún valor no cabe en el tipo declarado, pyarrow lanza un error aquí.
    return pa.Table.from_pandas(df, schema=contract.schema, preserve_index=False)


def extract_table(conn, contract: TableContract, low: str, load_id: str) -> tuple[int, str | None]:
    # 1. Congelar el límite superior ANTES de extraer. Lo que cambie mientras
    #    extraemos queda para la siguiente corrida, en lugar de perderse.
    high = conn.execute(
        text(f"SELECT MAX({contract.watermark}) FROM {contract.source}")
    ).scalar()
    if high is None:  # tabla vacía
        return 0, None
    high = high.isoformat(timespec="milliseconds")

    # 2. Lista explícita de columnas: si el origen agrega una columna, no nos
    #    afecta; si quita o renombra una, la consulta falla ruidosamente.
    #    Los watermarks viajan como texto ISO y se convierten en SQL Server:
    #    así no dependemos de cómo el driver traduzca las fechas de Python.
    columns = ", ".join(contract.schema.names)
    query = text(
        f"SELECT {columns} FROM {contract.source} "
        f"WHERE {contract.watermark} >  CAST(:low  AS DATETIME2(3)) "
        f"  AND {contract.watermark} <= CAST(:high AS DATETIME2(3))"
    )

    # 3. Carpeta temporal con "_" al inicio: Arrow y Spark ignoran esas
    #    carpetas al leer, así que nadie ve una carga incompleta.
    table_dir = BRONZE / contract.folder
    tmp_dir = table_dir / f"_inprogress_load_id={load_id}"
    final_dir = table_dir / f"load_id={load_id}"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    rows = 0
    chunks = pd.read_sql(
        query,
        conn,
        params={"low": low, "high": high},
        chunksize=CHUNK_SIZE,
        coerce_float=False,  # nunca convertir Decimal en float
    )
    for i, chunk in enumerate(chunks):
        if chunk.empty:
            continue
        table = to_arrow(chunk, contract)
        pq.write_table(table, tmp_dir / f"part-{i:05d}.parquet", compression="zstd")
        rows += len(chunk)

    if rows == 0:
        tmp_dir.rmdir()  # nada nuevo: no publicamos una carga vacía
        return 0, None

    # 4. Publicar: el renombrado hace visible la carga completa de un solo golpe.
    tmp_dir.rename(final_dir)
    return rows, high


def main() -> None:
    full = "--full" in sys.argv
    # Un mismo load_id para todas las tablas de esta corrida, en UTC
    load_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    watermarks = {} if full else load_watermarks()

    print(f"Corrida {load_id}   modo: {'FULL' if full else 'INCREMENTAL'}\n")
    print(f"{'Tabla':<26}{'Filas':>12}{'Segundos':>10}   Watermark")

    engine = get_engine()
    total_start = time.perf_counter()
    with engine.connect() as conn:
        for contract in TABLES:
            start = time.perf_counter()
            low = watermarks.get(contract.source, EPOCH)
            rows, high = extract_table(conn, contract, low, load_id)

            # 5. El watermark solo avanza DESPUÉS de publicar la carga. Si algo
            #    truena antes, la siguiente corrida repite ese tramo completo.
            if high is not None:
                watermarks[contract.source] = high
                save_watermarks(watermarks)

            elapsed = time.perf_counter() - start
            print(f"{contract.source:<26}{rows:>12,}{elapsed:>10.1f}   "
                  f"{watermarks.get(contract.source, '-')}")

    print(f"\nTotal: {time.perf_counter() - total_start:.1f} s")


# Este bloque solo corre cuando ejecutas el archivo directamente,
# no cuando otro archivo lo importa.
if __name__ == "__main__":
    main()
