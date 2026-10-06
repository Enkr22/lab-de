"""
extract_first.py
Primera extracción: lee una tabla completa de LabNomina y la guarda
como Parquet en la capa bronze del data lake local.

Se corre desde la raíz del repo, con el entorno virtual activo:
    python extract/extract_first.py
"""

# --- Imports: traer herramientas de otras librerías ----------------------
import os                      # leer variables de entorno
import time                    # medir cuánto tarda
from pathlib import Path       # manejar rutas de archivos sin pelearse con "\" y "/"

import pandas as pd            # tablas en memoria (DataFrames)
from dotenv import load_dotenv  # lee tu archivo .env
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

# --- Configuración -------------------------------------------------------
# Cambia esta variable por "payroll.PayrollMovement" en el paso 5.
TABLE = "payroll.Employment"
# --- Conexión ------------------------------------------------------------
# load_dotenv() lee el .env y lo carga como variables de entorno.
# Así las contraseñas nunca aparecen escritas en el código.
load_dotenv()

# URL.create arma la cadena de conexión y se encarga de "escapar" los
# caracteres especiales de la contraseña (puntos, símbolos, etc.).
url = URL.create(
    "mssql+pyodbc",
    username=os.environ["EXTRACT_USER"],
    password=os.environ["EXTRACT_PASSWORD"],
    host="127.0.0.1",          # IPv4 explícito: la lección del día 1
    port=1434,
    database="LabNomina",
    query={
        "driver": "ODBC Driver 18 for SQL Server",
        "TrustServerCertificate": "yes",   # lo mismo que la casilla de SSMS
    },
)
engine = create_engine(url)

# --- Extract -------------------------------------------------------------
# TABLE viene de nuestra configuración, nunca de un usuario: por eso aquí
# es seguro armar el SQL con un f-string. Con datos que escribe un usuario,
# esto sería una puerta abierta a inyección SQL.
start = time.perf_counter()
df = pd.read_sql(f"SELECT * FROM {TABLE}", engine)
extract_seconds = time.perf_counter() - start

# Un DataFrame es como el resultado de una consulta en SSMS,
# pero viviendo en la memoria de Python.
print(df.head())     # las primeras 5 filas
print(df.dtypes)     # el tipo de dato que pandas le asignó a cada columna

# --- Load: aterrizar en bronze -------------------------------------------
# Ruta: data/bronze/<esquema>/<tabla>/<tabla>.parquet
# La carpeta data/ está en el .gitignore: el código vive en git,
# los datos viven en el lake. Nunca al revés.
schema, name = TABLE.split(".")
output_dir = Path("data") / "bronze" / schema / name.lower()
output_dir.mkdir(parents=True, exist_ok=True)
output_file = output_dir / f"{name.lower()}.parquet"

start = time.perf_counter()
df.to_parquet(output_file, index=False)
write_seconds = time.perf_counter() - start

# --- Verificar: leer de vuelta lo que escribimos ------------------------
check = pd.read_parquet(output_file)
size_mb = output_file.stat().st_size / 1024 / 1024

print()
print(f"Tabla:            {TABLE}")
print(f"Filas extraídas:  {len(df):,}")
print(f"Filas en Parquet: {len(check):,}")
print(f"Extracción:       {extract_seconds:.1f} s")
print(f"Escritura:        {write_seconds:.1f} s")
print(f"Tamaño en disco:  {size_mb:.2f} MB")
print(f"Archivo:          {output_file}")
