"""
inspect_parquet.py
Muestra cuánto pesa cada columna de un archivo Parquet y con qué tipo
quedó guardada. No lee los datos: solo los metadatos del archivo.

    python extract/inspect_parquet.py
"""

import pyarrow.parquet as pq

FILE = "data/bronze/payroll/payrollmovement/payrollmovement.parquet"

parquet_file = pq.ParquetFile(FILE)
meta = parquet_file.metadata

# Un Parquet se divide en "row groups" (bloques de filas), y dentro de cada
# uno, cada columna se guarda por separado. Sumamos el tamaño comprimido
# de cada columna a través de todos los bloques.
sizes = {}
for rg in range(meta.num_row_groups):
    row_group = meta.row_group(rg)
    for c in range(row_group.num_columns):
        column = row_group.column(c)
        name = column.path_in_schema
        sizes[name] = sizes.get(name, 0) + column.total_compressed_size

total = sum(sizes.values())
print(f"Filas: {meta.num_rows:,}   Row groups: {meta.num_row_groups}\n")
print(f"{'Columna':<15}{'MB':>10}{'% del total':>14}")
for name, size in sorted(sizes.items(), key=lambda item: item[1], reverse=True):
    print(f"{name:<15}{size / 1024 / 1024:>10.2f}{size / total:>13.1%}")

print("\nTipos de dato con los que quedó guardada cada columna:")
print(parquet_file.schema_arrow)
import pandas as pd
df = pd.read_parquet("data/bronze/payroll/payrollmovement/payrollmovement.parquet", columns=["Amount"])
print(f"{df['Amount'].sum():.10f}")