-- explore.sql
-- Movimientos y monto total por país y año, leídos de silver.
-- Aquí sí tiene sentido sumar montos: cada fila es un solo país, una sola moneda.
--
-- Dos atajos de DuckDB que no existen en SQL Server:
--   GROUP BY ALL: agrupa por todas las columnas que no son agregadas.
--   ORDER BY ALL: ordena por todas las columnas, de izquierda a derecha.

SELECT
    p.CountryCode,
    YEAR(p.StartDate)  AS PayYear,
    COUNT(*)           AS Movements,
    SUM(m.Amount)      AS TotalAmount
FROM silver.payroll_movement AS m
JOIN silver.payroll_period   AS p USING (PeriodId)
GROUP BY ALL
ORDER BY ALL;
