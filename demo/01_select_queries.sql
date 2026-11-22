-- =====================================================================
-- demo/01_select_queries.sql — 19 SELECT-запитів із питанням користувача
-- Запуск: psql -d avia_mro_db -f demo/01_select_queries.sql
-- (запити Q16 і v_open_defects залежать від CURRENT_DATE)
-- =====================================================================
\pset null '—'

\echo
\echo '== Q01 [INNER JOIN] Які судна є в парку і якого вони типу?'
SELECT a.tail_number, t.manufacturer, t.model, a.total_flight_hours, a.status
FROM avia_mro.aircraft AS a
         JOIN avia_mro.aircraft_types AS t ON t.id = a.aircraft_type_id
ORDER BY a.tail_number;

\echo
\echo '== Q02 [LEFT JOIN + IS NULL] Які судна ще не мають жодного наряду?'
SELECT a.tail_number
FROM avia_mro.aircraft AS a
         LEFT JOIN avia_mro.work_orders AS wo ON wo.aircraft_id = a.id
WHERE wo.id IS NULL;

\echo
\echo '== Q03 [GROUP BY + FILTER] Скільки нарядів кожного статусу має кожне судно?'
SELECT a.tail_number,
       COUNT(*) FILTER (WHERE wo.status = 'planned')     AS planned,
    COUNT(*) FILTER (WHERE wo.status = 'in_progress') AS in_progress,
    COUNT(*) FILTER (WHERE wo.status = 'completed')   AS completed,
    COUNT(*) FILTER (WHERE wo.status = 'cancelled')   AS cancelled
FROM avia_mro.aircraft AS a
         JOIN avia_mro.work_orders AS wo ON wo.aircraft_id = a.id
GROUP BY a.tail_number
ORDER BY a.tail_number;

\echo
\echo '== Q04 [HAVING] Які працівники відпрацювали понад 30 людино-годин?'
SELECT e.full_name, SUM(t.hours_spent) AS total_hours
FROM avia_mro.employees AS e
         JOIN avia_mro.work_order_tasks AS t ON t.employee_id = e.id
GROUP BY e.id, e.full_name
HAVING SUM(t.hours_spent) > 30
ORDER BY total_hours DESC;

\echo
\echo '== Q05 [JOIN 3 таблиці] Які встановлені агрегати використали понад 90% ресурсу?'
SELECT c.serial_number, ct.name, a.tail_number,
       ROUND(100 * c.hours_since_overhaul / ct.overhaul_interval_hours, 1) AS pct_used
FROM avia_mro.components AS c
         JOIN avia_mro.component_types AS ct ON ct.id = c.component_type_id
         JOIN avia_mro.aircraft AS a ON a.id = c.aircraft_id
WHERE c.hours_since_overhaul >= 0.9 * ct.overhaul_interval_hours
ORDER BY pct_used DESC;

\echo
\echo '== Q06 [EXISTS] Які судна мають відкриті критичні дефекти?'
SELECT a.tail_number, a.status
FROM avia_mro.aircraft AS a
WHERE EXISTS (SELECT 1 FROM avia_mro.defects AS d
              WHERE d.aircraft_id = a.id
                AND d.status = 'open' AND d.severity = 'critical');

\echo
\echo '== Q07 [підзапит з агрегатом] Які роботи тривали довше за середню тривалість роботи?'
SELECT wo.order_number, t.description, t.hours_spent
FROM avia_mro.work_order_tasks AS t
         JOIN avia_mro.work_orders AS wo ON wo.id = t.work_order_id
WHERE t.hours_spent > (SELECT AVG(hours_spent) FROM avia_mro.work_order_tasks)
ORDER BY t.hours_spent DESC;

\echo
\echo '== Q08 [DISTINCT ON] Який останній за плановою датою наряд кожного судна?'
SELECT DISTINCT ON (wo.aircraft_id)
    a.tail_number, wo.order_number, wo.planned_date, wo.status
FROM avia_mro.work_orders AS wo
    JOIN avia_mro.aircraft AS a ON a.id = wo.aircraft_id
ORDER BY wo.aircraft_id, wo.planned_date DESC, wo.id DESC;

\echo
\echo '== Q09 [RANK, PARTITION BY] Рейтинг працівників за годинами в межах кваліфікації'
SELECT e.qualification, e.full_name, SUM(t.hours_spent) AS total_hours,
       RANK() OVER (PARTITION BY e.qualification
                    ORDER BY SUM(t.hours_spent) DESC) AS rank_in_group
FROM avia_mro.employees AS e
         JOIN avia_mro.work_order_tasks AS t ON t.employee_id = e.id
GROUP BY e.id, e.qualification, e.full_name
ORDER BY e.qualification, rank_in_group;

\echo
\echo '== Q10 [LAG] Скільки днів минуло між сусідніми нарядами одного судна?'
SELECT a.tail_number, wo.order_number, wo.planned_date,
       wo.planned_date - LAG(wo.planned_date)
           OVER (PARTITION BY wo.aircraft_id ORDER BY wo.planned_date, wo.id) AS days_since_prev
FROM avia_mro.work_orders AS wo
         JOIN avia_mro.aircraft AS a ON a.id = wo.aircraft_id
WHERE wo.status <> 'cancelled'
ORDER BY a.tail_number, wo.planned_date;

\echo
\echo '== Q11 [накопичувальна сума] Як зростають сумарні години ТО судна від наряду до наряду?'
WITH order_hours AS (
    SELECT wo.id, wo.aircraft_id, wo.order_number, wo.planned_date,
           SUM(t.hours_spent) AS hours
    FROM avia_mro.work_orders AS wo
    JOIN avia_mro.work_order_tasks AS t ON t.work_order_id = wo.id
    GROUP BY wo.id
)
SELECT a.tail_number, oh.order_number, oh.hours,
       SUM(oh.hours) OVER (PARTITION BY oh.aircraft_id
                           ORDER BY oh.planned_date, oh.id
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_hours
FROM order_hours AS oh
         JOIN avia_mro.aircraft AS a ON a.id = oh.aircraft_id
ORDER BY a.tail_number, oh.planned_date, oh.id;

\echo
\echo '== Q12 [CTE] У які місяці навантаження перевищувало середньомісячне?'
WITH monthly AS (
    SELECT date_trunc('month', wo.planned_date)::date AS month,
           SUM(t.hours_spent) AS hours
    FROM avia_mro.work_order_tasks AS t
    JOIN avia_mro.work_orders AS wo ON wo.id = t.work_order_id
    GROUP BY 1
)
SELECT month, hours,
    ROUND((SELECT AVG(hours) FROM monthly), 1) AS avg_month,
    hours > (SELECT AVG(hours) FROM monthly)  AS above_average
FROM monthly
ORDER BY month;

\echo
\echo '== Q13 [порівняння стовпців] Які запчастини нижче мінімального залишку?'
SELECT part_number, name, stock_qty, min_qty, min_qty - stock_qty AS shortage
FROM avia_mro.spare_parts
WHERE stock_qty < min_qty
ORDER BY shortage DESC;

\echo
\echo '== Q14 [JOIN + SUM] Які запчастини витрачаються найбільше?'
SELECT sp.part_number, sp.name, SUM(pu.quantity) AS used_qty,
       COUNT(*) AS used_in_tasks
FROM avia_mro.spare_parts AS sp
         JOIN avia_mro.part_usage AS pu ON pu.spare_part_id = sp.id
GROUP BY sp.id, sp.part_number, sp.name
ORDER BY used_qty DESC;

\echo
\echo '== Q15 [AVG по інтервалу] Який середній час усунення дефектів за серйозністю?'
SELECT severity,
       COUNT(*) AS resolved_count,
       ROUND(AVG(EXTRACT(EPOCH FROM (resolved_at - found_at)) / 3600), 1) AS avg_hours
FROM avia_mro.defects
WHERE status = 'resolved'
GROUP BY severity
ORDER BY avg_hours DESC;

\echo
\echo '== Q16 [HAVING + дати] Для яких суден прострочено періодичне ТО (станом на сьогодні)?'
SELECT a.tail_number, mt.code,
       MAX(wo.completed_at)::date                       AS last_done,
    MAX(wo.completed_at)::date + mt.interval_days    AS due_date,
            CURRENT_DATE - (MAX(wo.completed_at)::date + mt.interval_days) AS overdue_days
FROM avia_mro.work_orders AS wo
         JOIN avia_mro.aircraft AS a ON a.id = wo.aircraft_id
         JOIN avia_mro.maintenance_types AS mt ON mt.id = wo.maintenance_type_id
WHERE wo.status = 'completed' AND mt.interval_days IS NOT NULL
GROUP BY a.tail_number, mt.code, mt.interval_days
HAVING MAX(wo.completed_at)::date + mt.interval_days < CURRENT_DATE
ORDER BY overdue_days DESC;

\echo
\echo '== Q17 [NOT EXISTS] Які працівники не виконували жодної роботи?'
SELECT e.personnel_number, e.full_name
FROM avia_mro.employees AS e
WHERE NOT EXISTS (SELECT 1 FROM avia_mro.work_order_tasks AS t
                  WHERE t.employee_id = e.id);

\echo
\echo '== Q18 [представлення] Зведення ТО по суднах'
SELECT * FROM avia_mro.v_aircraft_maintenance_summary ORDER BY tail_number;

\echo
\echo '== Q19 [функції] Години ТО судна UR-AAA за липень–серпень 2026 і залишок ресурсу ENG-1001'
SELECT avia_mro.aircraft_maintenance_hours(
               (SELECT id FROM avia_mro.aircraft WHERE tail_number = 'UR-AAA'),
               DATE '2026-07-01', DATE '2026-09-01') AS hours_jul_aug,
       avia_mro.component_resource_left(
               (SELECT id FROM avia_mro.components WHERE serial_number = 'ENG-1001')) AS eng_1001_hours_left;
