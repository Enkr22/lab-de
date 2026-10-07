-- Por defecto, dbt nombra los esquemas como <esquema_base>_<esquema_custom>
-- (por ejemplo, main_staging). Este macro usa el nombre exacto: staging.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
