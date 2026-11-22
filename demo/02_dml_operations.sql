-- =====================================================================
-- demo/02_dml_operations.sql — операції зміни даних (INSERT, UPDATE,
-- UPSERT, DELETE, RETURNING). Усе виконується в транзакції з ROLLBACK
-- наприкінці, тому скрипт можна запускати багаторазово.
-- =====================================================================
\pset null '—'
BEGIN;

\echo
\echo '== M1 [INSERT через функцію] Створити наряд A-check для UR-EEB'
SELECT avia_mro.create_work_order(a.id, m.id, DATE '2026-12-20') AS new_order_id
FROM avia_mro.aircraft AS a, avia_mro.maintenance_types AS m
WHERE a.tail_number = 'UR-EEB' AND m.code = 'A-CHECK'
    \gset
SELECT id, order_number, status, planned_date
FROM avia_mro.work_orders WHERE id = :new_order_id;

\echo
\echo '== M2 [UPDATE через процедуру] Розпочати наряд (тригери: перевірка переходу + аудит)'
CALL avia_mro.start_work_order(:new_order_id);
SELECT wo.status, wo.started_at IS NOT NULL AS started_set, a.status AS aircraft_status
FROM avia_mro.work_orders AS wo
         JOIN avia_mro.aircraft AS a ON a.id = wo.aircraft_id
WHERE wo.id = :new_order_id;
SELECT table_name, record_id, field_name, old_value, new_value, changed_by
FROM avia_mro.audit_log WHERE record_id = :new_order_id;

\echo
\echo '== M3 [INSERT ... RETURNING] Додати роботу до наряду'
INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent, result)
SELECT :new_order_id, e.id, 'Огляд планера', 8.0, 'ok'
FROM avia_mro.employees AS e WHERE e.personnel_number = 'P006'
    RETURNING id, work_order_id, description, hours_spent;

\echo
\echo '== M4 [UPSERT] Надходження запчастин: наявна SP-SEAL-22 (+10) і нова SP-NEW-01'
INSERT INTO avia_mro.spare_parts (part_number, name, stock_qty, min_qty)
VALUES ('SP-SEAL-22', 'Ущільнювач гідросистеми', 10, 10),
       ('SP-NEW-01',  'Датчик тиску',            6,  2)
ON CONFLICT (part_number)
DO UPDATE SET stock_qty = avia_mro.spare_parts.stock_qty + EXCLUDED.stock_qty
        RETURNING part_number, stock_qty, (xmax = 0) AS inserted;

\echo
\echo '== M5 [UPDATE ... RETURNING] Після польотів додати 120.5 год до ресурсу агрегатів UR-AAA'
UPDATE avia_mro.components AS c
SET hours_since_overhaul = c.hours_since_overhaul + 120.5
    FROM avia_mro.aircraft AS a
WHERE a.id = c.aircraft_id AND a.tail_number = 'UR-AAA'
    RETURNING c.serial_number, c.hours_since_overhaul;

\echo
\echo '== M6 [процедура з OUT-параметром] Завершити наряд, отримати сумарні години'
CALL avia_mro.complete_work_order(:new_order_id, NULL);
SELECT status, completed_at IS NOT NULL AS completed_set
FROM avia_mro.work_orders WHERE id = :new_order_id;

\echo
\echo '== M7 [DELETE ... RETURNING] Видалити скасований наряд без робіт WO-2026-0009'
DELETE FROM avia_mro.work_orders
WHERE order_number = 'WO-2026-0009' AND status = 'cancelled'
    RETURNING id, order_number, status;

\echo
\echo '== Відкат: база повертається до початкового стану'
ROLLBACK;
SELECT COUNT(*) AS work_orders_after_rollback FROM avia_mro.work_orders;
