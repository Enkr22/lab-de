# Imagen de Airflow para el lab:
#   Airflow oficial + un entorno virtual aparte con las dependencias del pipeline.
# Se construye desde la raíz del repo (ver docker-compose.yml).

# Misma versión de Python que tu laptop (3.13): el mismo requirements.txt sirve en ambos lados.
# La imagen oficial ya trae el driver "ODBC Driver 18 for SQL Server" (en amd64),
# así que no hay que instalarlo.
FROM apache/airflow:3.3.2-python3.13

USER root

# Entorno virtual del pipeline, SEPARADO del de Airflow: las versiones de
# dbt, pandas, etc. nunca chocan con las que Airflow necesita.
# Usa tu mismo lockfile: el contenedor corre exactamente las versiones de tu laptop.
COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /opt/pipeline-venv \
 && /opt/pipeline-venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt

USER airflow
