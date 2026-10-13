"""
payroll_pipeline.py
DAG del laboratorio: SQL Server -> bronze (Parquet) -> dbt (staging y marts)
-> export de los marts para Power BI.

Este archivo NO ejecuta nada por sí mismo: solo DESCRIBE el pipeline.
Airflow lo lee, entiende qué tareas hay y en qué orden van, y el
scheduler se encarga de correrlas a su hora.
"""

from datetime import timedelta

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

PROJECT = "/opt/lab-de"           # el repo, montado dentro del contenedor
VENV = "/opt/pipeline-venv/bin"   # el entorno del pipeline, separado del de Airflow

with DAG(
    dag_id="payroll_pipeline",
    description="SQL Server -> bronze -> dbt -> export para BI",
    schedule="0 2 * * *",         # todos los días a las 2:00 a. m.
    start_date=pendulum.datetime(2026, 10, 1, tz="America/Mexico_City"),
    catchup=False,                # no "reponer" los días anteriores al start_date
    max_active_runs=1,            # nunca dos corridas a la vez sobre los mismos archivos
    default_args={
        "retries": 2,                         # si una tarea truena, se reintenta 2 veces
        "retry_delay": timedelta(minutes=5),  # esperando 5 minutos entre intentos
    },
    tags=["lab-de"],
) as dag:

    extract_to_bronze = BashOperator(
        task_id="extract_to_bronze",
        bash_command=f"cd {PROJECT} && {VENV}/python extract/extract.py",
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=f"cd {PROJECT}/transform && {VENV}/dbt build",
    )

    export_for_bi = BashOperator(
        task_id="export_for_bi",
        bash_command=f"cd {PROJECT} && {VENV}/python serving/export_for_bi.py",
    )

    # El DAG en una línea: cada tarea solo arranca si la anterior terminó bien.
    # Si las pruebas de dbt fallan, Power BI se queda con el último export bueno.
    extract_to_bronze >> dbt_build >> export_for_bi
