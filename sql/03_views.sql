-- =====================================================================
-- 03_views.sql — представлення
-- =====================================================================

-- Зведення по кожному судну: кількість нарядів і витрачені людино-години
CREATE VIEW avia_mro.v_aircraft_maintenance_summary AS
SELECT a.tail_number,
       t.type_code,
       a.status,
       COUNT(wo.id)                                   AS total_orders,
       COUNT(wo.id) FILTER (WHERE wo.status = 'completed')   AS completed_orders,
    COUNT(wo.id) FILTER (WHERE wo.status IN ('planned', 'in_progress')) AS open_orders,
    COALESCE(SUM(th.hours), 0)                     AS total_hours
FROM avia_mro.aircraft AS a
         JOIN avia_mro.aircraft_types AS t ON t.id = a.aircraft_type_id
         LEFT JOIN avia_mro.work_orders AS wo ON wo.aircraft_id = a.id
         LEFT JOIN (SELECT work_order_id, SUM(hours_spent) AS hours
                    FROM avia_mro.work_order_tasks
                    GROUP BY work_order_id) AS th ON th.work_order_id = wo.id
GROUP BY a.id, a.tail_number, t.type_code, a.status;

-- Використання ресурсу агрегатів
CREATE VIEW avia_mro.v_components_resource AS
SELECT c.id AS component_id,
       ct.part_number,
       ct.name,
       c.serial_number,
       a.tail_number,
       c.hours_since_overhaul,
       ct.overhaul_interval_hours,
       ct.overhaul_interval_hours - c.hours_since_overhaul        AS hours_left,
       ROUND(100 * c.hours_since_overhaul / ct.overhaul_interval_hours, 1) AS pct_used,
       CASE
           WHEN c.hours_since_overhaul >= 0.90 * ct.overhaul_interval_hours THEN 'critical'
           WHEN c.hours_since_overhaul >= 0.75 * ct.overhaul_interval_hours THEN 'warning'
           ELSE 'ok'
           END AS resource_state
FROM avia_mro.components AS c
         JOIN avia_mro.component_types AS ct ON ct.id = c.component_type_id
         LEFT JOIN avia_mro.aircraft AS a ON a.id = c.aircraft_id;

-- Відкриті дефекти зі строком «висіння»
CREATE VIEW avia_mro.v_open_defects AS
SELECT d.id AS defect_id,
       a.tail_number,
       c.serial_number AS component_serial,
       d.severity,
       d.description,
       d.found_at,
       (CURRENT_DATE - d.found_at::date) AS days_open
FROM avia_mro.defects AS d
         JOIN avia_mro.aircraft AS a ON a.id = d.aircraft_id
         LEFT JOIN avia_mro.components AS c ON c.id = d.component_id
WHERE d.status = 'open';
