{#
    Backfill único (DATA-1423): llena contract_type en las versiones VIGENTES
    del snapshot con el valor actual de staging. Las versiones cerradas se
    quedan en NULL: no sabemos qué tipo de contrato tenían en ese momento.
    Idempotente: solo toca filas vigentes que sigan en NULL.
    Uso: dbt run-operation backfill_snapshot_contract_type
#}
{% macro backfill_snapshot_contract_type() %}
    {% set sql %}
        update {{ ref('snp_employment') }} as s
        set contract_type = e.contract_type
        from {{ ref('stg_employment') }} as e
        where e.employment_id = s.employment_id
          and s.dbt_valid_to = cast('9999-12-31' as timestamp)
          and s.contract_type is null
          and e.contract_type is not null
    {% endset %}
    {% set result = run_query(sql) %}
    {{ log("Versiones vigentes actualizadas: " ~ result.columns[0].values()[0], info=True) }}
{% endmacro %}