-- =====================================================================
-- tests/tests.sql — автоматизовані тести (43 перевірки)
-- Запуск: scripts/run_tests.sh   (або psql -d avia_mro_db -f tests/tests.sql)
-- Уся робота виконується в одній транзакції з ROLLBACK наприкінці:
-- початкові дані бази не змінюються, тести можна повторювати.
-- Початковий стан = дані з sql/02_seed.sql.
-- =====================================================================
\set ON_ERROR_STOP on
\pset null '—'
BEGIN;

CREATE TEMP TABLE test_results (
    seq      serial,
    code     text,
    descr    text,
    expected text,
    actual   text,
    ok       boolean
);

-- Очікується помилка з певним SQLSTATE (або 'no error', якщо команда має пройти)
CREATE FUNCTION pg_temp.expect_error(p_code text, p_descr text, p_sql text, p_expected text)
    RETURNS void LANGUAGE plpgsql AS $$
DECLARE
v_state text := 'no error';
BEGIN
BEGIN
EXECUTE p_sql;
EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
END;
    RESET ROLE;
INSERT INTO test_results (code, descr, expected, actual, ok)
VALUES (p_code, p_descr, p_expected, v_state, v_state = p_expected);
END $$;

-- Очікується певне текстове значення результату запиту
CREATE FUNCTION pg_temp.expect_value(p_code text, p_descr text, p_sql text, p_expected text)
    RETURNS void LANGUAGE plpgsql AS $$
DECLARE
v text;
BEGIN
EXECUTE p_sql INTO v;
RESET ROLE;
INSERT INTO test_results (code, descr, expected, actual, ok)
VALUES (p_code, p_descr, p_expected, v, v IS NOT DISTINCT FROM p_expected);
END $$;

\o /dev/null
-- ================= Функції та створення наряду (позитивний / негативний) =================
SELECT pg_temp.expect_value('T01', 'create_work_order: коректний виклик повертає id наряду',
                            $q$SELECT (avia_mro.create_work_order(a.id, m.id, DATE '2026-12-20') > 0)::text
    FROM avia_mro.aircraft a, avia_mro.maintenance_types m
    WHERE a.tail_number = 'UR-EEB' AND m.code = 'A-CHECK'$q$, 'true');

SELECT pg_temp.expect_error('T02', 'create_work_order: другий відкритий наряд того ж виду (BR12) відхилено',
                            $q$SELECT avia_mro.create_work_order(a.id, m.id, DATE '2026-12-25')
    FROM avia_mro.aircraft a, avia_mro.maintenance_types m
    WHERE a.tail_number = 'UR-EEB' AND m.code = 'A-CHECK'$q$, 'P0001');

-- ================= Обмеження цілісності (негативні) =================
SELECT pg_temp.expect_error('T03', 'UNIQUE: повторний бортовий номер UR-AAA (BR01) -> unique_violation',
                            $q$INSERT INTO avia_mro.aircraft (tail_number, aircraft_type_id, serial_number, manufactured_year)
    SELECT 'UR-AAA', id, 'X1', 2020 FROM avia_mro.aircraft_types WHERE type_code = 'A320'$q$, '23505');

SELECT pg_temp.expect_error('T04', 'CHECK: неправильний формат бортового номера (BR01) -> check_violation',
                            $q$INSERT INTO avia_mro.aircraft (tail_number, aircraft_type_id, serial_number, manufactured_year)
    SELECT 'ur-1', id, 'X2', 2020 FROM avia_mro.aircraft_types WHERE type_code = 'A320'$q$, '23514');

SELECT pg_temp.expect_error('T05', 'CHECK: від''ємний наліт судна (BR02) -> check_violation',
                            $q$UPDATE avia_mro.aircraft SET total_flight_hours = -1 WHERE tail_number = 'UR-AAA'$q$, '23514');

SELECT pg_temp.expect_error('T06', 'FOREIGN KEY ... RESTRICT: видалення судна з нарядами (BR04) -> foreign_key_violation',
                            $q$DELETE FROM avia_mro.aircraft WHERE tail_number = 'UR-AAA'$q$, '23503');

SELECT pg_temp.expect_error('T07', 'FOREIGN KEY: наряд для неіснуючого судна (BR03) -> foreign_key_violation',
                            $q$INSERT INTO avia_mro.work_orders (order_number, aircraft_id, maintenance_type_id, planned_date)
    VALUES ('WO-TEST-1', -1, (SELECT id FROM avia_mro.maintenance_types LIMIT 1), DATE '2026-12-01')$q$, '23503');

SELECT pg_temp.expect_error('T08', 'CHECK: завершення раніше початку (BR05) -> check_violation',
                            $q$INSERT INTO avia_mro.work_orders (order_number, aircraft_id, maintenance_type_id, status,
                                      planned_date, started_at, completed_at)
    SELECT 'WO-TEST-2', a.id, m.id, 'completed', DATE '2026-11-01',
                            TIMESTAMPTZ '2026-11-01 10:00+02', TIMESTAMPTZ '2026-11-01 09:00+02'
    FROM avia_mro.aircraft a, avia_mro.maintenance_types m
    WHERE a.tail_number = 'UR-EEB' AND m.code = 'UNSCHED'$q$, '23514');

-- ================= Тригер переходу статусу та контроль відкритого наряду =================
SELECT pg_temp.expect_error('T09', 'Тригер BEFORE: перехід completed -> planned заборонено (BR06)',
                            $q$UPDATE avia_mro.work_orders SET status = 'planned' WHERE order_number = 'WO-2026-0001'$q$, 'P0001');

SELECT pg_temp.expect_error('T10', 'Тригер BEFORE: перехід planned -> completed (пропуск етапу) заборонено (BR06)',
                            $q$UPDATE avia_mro.work_orders SET status = 'completed' WHERE order_number = 'WO-2026-0008'$q$, 'P0001');

SELECT pg_temp.expect_error('T11', 'Тригер: додавання роботи до завершеного наряду заборонено (BR09)',
                            $q$INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent)
    SELECT wo.id, e.id, 'Тест', 1
                                FROM avia_mro.work_orders wo, avia_mro.employees e
    WHERE wo.order_number = 'WO-2026-0001' AND e.personnel_number = 'P001'$q$, 'P0001');

-- ================= Граничні значення тривалості роботи (BR10) =================
SELECT pg_temp.expect_error('T12', 'Межа: 24.00 год на роботу допустимо',
                            $q$INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent)
    SELECT wo.id, e.id, 'Межа 24', 24.00
                                FROM avia_mro.work_orders wo, avia_mro.employees e
    WHERE wo.order_number = 'WO-2026-0003' AND e.personnel_number = 'P001'$q$, 'no error');

SELECT pg_temp.expect_error('T13', 'Межа: 24.01 год відхилено -> check_violation',
                            $q$INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent)
    SELECT wo.id, e.id, 'Межа 24.01', 24.01
                                FROM avia_mro.work_orders wo, avia_mro.employees e
    WHERE wo.order_number = 'WO-2026-0003' AND e.personnel_number = 'P001'$q$, '23514');

SELECT pg_temp.expect_error('T14', 'Межа: 0 год відхилено -> check_violation',
                            $q$INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent)
    SELECT wo.id, e.id, 'Нуль годин', 0
                                FROM avia_mro.work_orders wo, avia_mro.employees e
    WHERE wo.order_number = 'WO-2026-0003' AND e.personnel_number = 'P001'$q$, '23514');

-- ================= Запчастини (BR07) =================
SELECT pg_temp.expect_error('T15', 'use_spare_part: списання 5 шт. при залишку 3 відхилено',
                            format($q$CALL avia_mro.use_spare_part(%s, %s, 5)$q$,
                                   (SELECT t.id FROM avia_mro.work_order_tasks t JOIN avia_mro.work_orders wo ON wo.id = t.work_order_id
                                    WHERE wo.order_number = 'WO-2026-0003' AND t.description = 'Розбирання панелей'),
                                   (SELECT id FROM avia_mro.spare_parts WHERE part_number = 'SP-BRK-05')), 'P0001');

SELECT pg_temp.expect_value('T16', 'use_spare_part: після відмови залишок SP-BRK-05 не змінився',
                            $q$SELECT stock_qty::text FROM avia_mro.spare_parts WHERE part_number = 'SP-BRK-05'$q$, '3');

SELECT pg_temp.expect_error('T17', 'use_spare_part: коректне списання 2 шт.',
                            format($q$CALL avia_mro.use_spare_part(%s, %s, 2)$q$,
                                   (SELECT t.id FROM avia_mro.work_order_tasks t JOIN avia_mro.work_orders wo ON wo.id = t.work_order_id
                                    WHERE wo.order_number = 'WO-2026-0003' AND t.description = 'Розбирання панелей'),
                                   (SELECT id FROM avia_mro.spare_parts WHERE part_number = 'SP-BRK-05')), 'no error');

SELECT pg_temp.expect_value('T18', 'use_spare_part: залишок SP-BRK-05 зменшився до 1',
                            $q$SELECT stock_qty::text FROM avia_mro.spare_parts WHERE part_number = 'SP-BRK-05'$q$, '1');

SELECT pg_temp.expect_error('T19', 'use_spare_part: від''ємна кількість відхилена',
                            format($q$CALL avia_mro.use_spare_part(%s, %s, -1)$q$,
                                   (SELECT t.id FROM avia_mro.work_order_tasks t JOIN avia_mro.work_orders wo ON wo.id = t.work_order_id
                                    WHERE wo.order_number = 'WO-2026-0003' AND t.description = 'Розбирання панелей'),
                                   (SELECT id FROM avia_mro.spare_parts WHERE part_number = 'SP-BRK-05')), 'P0001');

SELECT pg_temp.expect_error('T20', 'use_spare_part: списання на роботу завершеного наряду відхилено',
                            format($q$CALL avia_mro.use_spare_part(%s, %s, 1)$q$,
                                   (SELECT t.id FROM avia_mro.work_order_tasks t JOIN avia_mro.work_orders wo ON wo.id = t.work_order_id
                                    WHERE wo.order_number = 'WO-2026-0001' AND t.description = 'Змащення шасі'),
                                   (SELECT id FROM avia_mro.spare_parts WHERE part_number = 'SP-BLT-10')), 'P0001');

-- ================= Аудит: COMMIT-подібна зміна =================
SELECT pg_temp.expect_error('T21', 'Зміна статусу WO-2026-0008 planned -> in_progress проходить',
                            $q$UPDATE avia_mro.work_orders SET status = 'in_progress' WHERE order_number = 'WO-2026-0008'$q$, 'no error');

SELECT pg_temp.expect_value('T22', 'Тригер AFTER: у audit_log з''явився рівно один запис planned -> in_progress',
                            $q$SELECT COUNT(*)::text FROM avia_mro.audit_log al
    JOIN avia_mro.work_orders wo ON wo.id = al.record_id
    WHERE wo.order_number = 'WO-2026-0008' AND al.old_value = 'planned' AND al.new_value = 'in_progress'$q$, '1');

SELECT pg_temp.expect_value('T23', 'Тригер BEFORE: started_at проставлено автоматично',
                            $q$SELECT (started_at IS NOT NULL)::text FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0008'$q$, 'true');

-- ================= Аудит: ROLLBACK скасовує і зміну, і запис журналу =================
DO $$
DECLARE
v_in_tx  integer;
    v_after  integer;
    v_id     bigint;
BEGIN
SELECT id INTO v_id FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0010';
BEGIN
UPDATE avia_mro.work_orders SET status = 'in_progress' WHERE id = v_id;
SELECT COUNT(*) INTO v_in_tx FROM avia_mro.audit_log WHERE record_id = v_id;
RAISE EXCEPTION 'rollback_marker';          -- імітація ROLLBACK підтранзакції
EXCEPTION WHEN raise_exception THEN
        NULL;
END;
SELECT COUNT(*) INTO v_after FROM avia_mro.audit_log WHERE record_id = v_id;
INSERT INTO test_results (code, descr, expected, actual, ok)
VALUES ('T24', 'Відкат транзакції скасовує зміну статусу й запис аудиту (у транзакції 1, після відкату 0)',
        '1 / 0', v_in_tx || ' / ' || v_after, v_in_tx = 1 AND v_after = 0);
END $$;

-- ================= Процедури життєвого циклу наряду =================
SELECT pg_temp.expect_error('T25', 'start_work_order: наряд WO-2026-0010 planned -> in_progress',
                            format($q$CALL avia_mro.start_work_order(%s)$q$,
                                   (SELECT id FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0010')), 'no error');

SELECT pg_temp.expect_value('T26', 'start_work_order: судно UR-BBA перейшло в in_maintenance',
                            $q$SELECT status FROM avia_mro.aircraft WHERE tail_number = 'UR-BBA'$q$, 'in_maintenance');

SELECT pg_temp.expect_error('T27', 'start_work_order: повторний запуск того ж наряду відхилено',
                            format($q$CALL avia_mro.start_work_order(%s)$q$,
                                   (SELECT id FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0010')), 'P0001');

SELECT pg_temp.expect_error('T28', 'complete_work_order: наряд без робіт завершити не можна',
                            format($q$CALL avia_mro.complete_work_order(%s, NULL)$q$,
                                   (SELECT id FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0010')), 'P0001');

SELECT pg_temp.expect_error('T29', 'complete_work_order: наряд із pending-роботами (WO-2026-0003) завершити не можна',
                            format($q$CALL avia_mro.complete_work_order(%s, NULL)$q$,
                                   (SELECT id FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0003')), 'P0001');

DO $$
DECLARE
v_id    bigint;
    v_total numeric;
    v_ac    text;
BEGIN
SELECT id INTO v_id FROM avia_mro.work_orders WHERE order_number = 'WO-2026-0010';
INSERT INTO avia_mro.work_order_tasks (work_order_id, employee_id, description, hours_spent, result)
SELECT v_id, e.id, 'Огляд планера', 5, 'ok'
FROM avia_mro.employees e WHERE e.personnel_number = 'P003';
CALL avia_mro.complete_work_order(v_id, v_total);
SELECT status INTO v_ac FROM avia_mro.aircraft WHERE tail_number = 'UR-BBA';
INSERT INTO test_results (code, descr, expected, actual, ok)
VALUES ('T30', 'complete_work_order: після додавання роботи 5 год наряд завершено, OUT-параметр = 5.00',
        '5.00', v_total::text, v_total = 5);
INSERT INTO test_results (code, descr, expected, actual, ok)
VALUES ('T31', 'complete_work_order: судно UR-BBA знову active (інших робочих нарядів немає)',
        'active', v_ac, v_ac = 'active');
END $$;

-- ================= Права доступу (ролі) =================
SELECT pg_temp.expect_error('T32', 'Аналітик: INSERT у spare_parts заборонено -> insufficient_privilege',
                            $q$SET LOCAL ROLE mro_analyst;
INSERT INTO avia_mro.spare_parts (part_number, name) VALUES ('X-1', 'Тест')$q$, '42501');

SELECT pg_temp.expect_error('T33', 'Аналітик: читання представлення v_open_defects дозволено',
                            $q$SET LOCAL ROLE mro_analyst;
SELECT * FROM avia_mro.v_open_defects$q$, 'no error');

SELECT pg_temp.expect_error('T34', 'Аналітик: читання audit_log дозволено',
                            $q$SET LOCAL ROLE mro_analyst;
SELECT * FROM avia_mro.audit_log$q$, 'no error');

SELECT pg_temp.expect_error('T35', 'Інженер: прямий UPDATE залишків spare_parts заборонено',
                            $q$SET LOCAL ROLE mro_engineer;
UPDATE avia_mro.spare_parts SET stock_qty = 999$q$, '42501');

SELECT pg_temp.expect_error('T36', 'Інженер: прямий INSERT в audit_log заборонено',
                            $q$SET LOCAL ROLE mro_engineer;
INSERT INTO avia_mro.audit_log (table_name, record_id, field_name) VALUES ('x', 1, 'y')$q$, '42501');

SELECT pg_temp.expect_error('T37', 'Інженер: списання запчастини через процедуру (SECURITY DEFINER) дозволено',
                            format($q$SET LOCAL ROLE mro_engineer;
CALL avia_mro.use_spare_part(%s, %s, 1)$q$,
        (SELECT t.id FROM avia_mro.work_order_tasks t JOIN avia_mro.work_orders wo ON wo.id = t.work_order_id
          WHERE wo.order_number = 'WO-2026-0003' AND t.description = 'Розбирання панелей'),
        (SELECT id FROM avia_mro.spare_parts WHERE part_number = 'SP-BLT-10')), 'no error');

SELECT pg_temp.expect_error('T38', 'Інженер: створення наряду (потрібен USAGE на послідовність) дозволено',
                            format($q$SET LOCAL ROLE mro_engineer;
SELECT avia_mro.create_work_order(%s, %s, DATE '2027-01-10')$q$,
       (SELECT id FROM avia_mro.aircraft WHERE tail_number = 'UR-BBB'),
       (SELECT id FROM avia_mro.maintenance_types WHERE code = 'ENG-INSP')), 'no error');

-- ================= Функції та представлення =================
SELECT pg_temp.expect_value('T39', 'aircraft_maintenance_hours: UR-AAA, липень–серпень 2026 = 48.50',
                            $q$SELECT avia_mro.aircraft_maintenance_hours(
        (SELECT id FROM avia_mro.aircraft WHERE tail_number = 'UR-AAA'),
        DATE '2026-07-01', DATE '2026-09-01')::text$q$, '48.50');

SELECT pg_temp.expect_value('T40', 'aircraft_maintenance_hours: межа півінтервалу — наряд 10.07 при to = 10.07 не враховано (0)',
                            $q$SELECT avia_mro.aircraft_maintenance_hours(
        (SELECT id FROM avia_mro.aircraft WHERE tail_number = 'UR-AAA'),
        DATE '2026-07-01', DATE '2026-07-10')::text$q$, '0');

SELECT pg_temp.expect_value('T41', 'component_resource_left: ENG-1001 = 20000 - 17500 = 2500.0',
                            $q$SELECT avia_mro.component_resource_left(
        (SELECT id FROM avia_mro.components WHERE serial_number = 'ENG-1001'))::text$q$, '2500.0');

SELECT pg_temp.expect_value('T42', 'component_resource_left: неіснуючий агрегат -> NULL',
                            $q$SELECT COALESCE(avia_mro.component_resource_left(-1)::text, 'NULL')$q$, 'NULL');

SELECT pg_temp.expect_value('T43', 'v_components_resource: 6 агрегатів у стані critical (>= 90% ресурсу; серед них HP-3003 на складі)',
                            $q$SELECT COUNT(*)::text FROM avia_mro.v_components_resource WHERE resource_state = 'critical'$q$, '6');

\o
-- ================= Протокол =================
\echo
\echo '=== ПРОТОКОЛ ТЕСТУВАННЯ ==='
SELECT code, descr AS "Перевірка", expected AS "Очікується", actual AS "Фактично",
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS "Результат"
FROM test_results ORDER BY seq;

SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE ok)     AS passed,
    COUNT(*) FILTER (WHERE NOT ok) AS failed
FROM test_results;

ROLLBACK;
