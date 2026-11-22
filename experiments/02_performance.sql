-- =====================================================================
-- experiments/02_performance.sql — дослідження швидкодії запитів та
-- впливу складеного покривного індексу (п. 5.9, с. 20).
-- Уся генерація виконується в транзакції з ROLLBACK наприкінці.
-- Запуск: docker exec -i avia_mro_postgres psql -U postgres -d avia_mro_db -f /project/experiments/02_performance.sql
-- =====================================================================
\pset null '—'
BEGIN;

\echo '== 1. Генерація 100 000 тестових робіт для відкритого наряду (in_progress) =='
INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent, result)
SELECT (SELECT id FROM avia_mro.work_orders WHERE status = 'in_progress' LIMIT 1),
       (1 + (g % 6)),
       'Планова перевірка вузла #' || g,
       2.5,
       CASE WHEN g % 3 = 0 THEN 'defect' ELSE 'ok' END
FROM generate_series(1, 100000) AS g;

ANALYZE avia_mro.work_order_tasks;

\echo '== 2. План виконання ДО створення складеного індексу (Seq Scan / Parallel Seq Scan) =='
EXPLAIN (ANALYZE, BUFFERS)
SELECT employee_id, SUM(hours_spent)
FROM avia_mro.work_order_tasks
WHERE employee_id = 3 AND result = 'defect'
GROUP BY employee_id;

\echo '== 3. Створення складеного покривного індексу =='
CREATE INDEX idx_tasks_emp_res
    ON avia_mro.work_order_tasks (employee_id, result)
    INCLUDE (hours_spent);

ANALYZE avia_mro.work_order_tasks;

\echo '== 4. План виконання ПІСЛЯ створення індексу (Index Only Scan) =='
EXPLAIN (ANALYZE, BUFFERS)
SELECT employee_id, SUM(hours_spent)
FROM avia_mro.work_order_tasks
WHERE employee_id = 3 AND result = 'defect'
GROUP BY employee_id;

ROLLBACK;