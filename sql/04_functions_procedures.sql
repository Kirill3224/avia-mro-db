-- =====================================================================
-- 04_functions_procedures.sql — функції та процедури
-- =====================================================================

-- ---------------------------------------------------------------------
-- Ф1. SQL-функція: сума людино-годин на судні за півінтервал [p_from, p_to)
--     за плановою датою наряду. Повертає 0, якщо робіт немає.
-- ---------------------------------------------------------------------
CREATE FUNCTION avia_mro.aircraft_maintenance_hours(
    p_aircraft_id integer, p_from date, p_to date
) RETURNS numeric
    LANGUAGE sql STABLE
AS $$
SELECT COALESCE(SUM(t.hours_spent), 0)
FROM avia_mro.work_order_tasks AS t
         JOIN avia_mro.work_orders AS wo ON wo.id = t.work_order_id
WHERE wo.aircraft_id = p_aircraft_id
  AND wo.planned_date >= p_from
  AND wo.planned_date <  p_to;
$$;

-- ---------------------------------------------------------------------
-- Ф2. SQL-функція: залишок ресурсу агрегата в годинах.
--     Повертає NULL, якщо агрегата з таким id немає.
--     STABLE, бо функція читає таблиці, що змінюються.
-- ---------------------------------------------------------------------
CREATE FUNCTION avia_mro.component_resource_left(p_component_id integer)
    RETURNS numeric
    LANGUAGE sql STABLE
AS $$
SELECT ct.overhaul_interval_hours - c.hours_since_overhaul
FROM avia_mro.components AS c
         JOIN avia_mro.component_types AS ct ON ct.id = c.component_type_id
WHERE c.id = p_component_id;
$$;

-- ---------------------------------------------------------------------
-- Ф3. PL/pgSQL-функція: створення наряду з перевірками.
--     Блокує рядок судна (FOR UPDATE), щоб два одночасні виклики не
--     створили дублікат відкритого наряду того самого виду.
-- ---------------------------------------------------------------------
CREATE FUNCTION avia_mro.create_work_order(
    p_aircraft_id integer, p_maintenance_type_id integer, p_planned_date date
) RETURNS bigint
    LANGUAGE plpgsql
AS $$
DECLARE
v_id bigint;
BEGIN
    PERFORM 1 FROM avia_mro.aircraft WHERE id = p_aircraft_id FOR UPDATE;
IF NOT FOUND THEN
        RAISE EXCEPTION 'Судно з id=% не знайдено', p_aircraft_id;
END IF;

    IF EXISTS (SELECT 1
               FROM avia_mro.work_orders
               WHERE aircraft_id = p_aircraft_id
                 AND maintenance_type_id = p_maintenance_type_id
                 AND status IN ('planned', 'in_progress')) THEN
        RAISE EXCEPTION 'Для судна % вже існує відкритий наряд цього виду', p_aircraft_id;
END IF;

INSERT INTO avia_mro.work_orders (order_number, aircraft_id, maintenance_type_id, planned_date)
VALUES ('WO-' || to_char(p_planned_date, 'YYYY') || '-' ||
        lpad(nextval('avia_mro.work_order_number_seq')::text, 4, '0'),
        p_aircraft_id, p_maintenance_type_id, p_planned_date)
    RETURNING id INTO v_id;

RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------
-- П1. Процедура: початок виконання наряду.
--     Статус судна active -> in_maintenance (grounded не змінюється).
-- ---------------------------------------------------------------------
CREATE PROCEDURE avia_mro.start_work_order(IN p_order_id bigint)
    LANGUAGE plpgsql
AS $$
DECLARE
v_aircraft integer;
BEGIN
UPDATE avia_mro.work_orders
SET status = 'in_progress'
WHERE id = p_order_id AND status = 'planned'
    RETURNING aircraft_id INTO v_aircraft;

IF NOT FOUND THEN
        RAISE EXCEPTION 'Наряд % не існує або не перебуває у статусі planned', p_order_id;
END IF;

UPDATE avia_mro.aircraft
SET status = 'in_maintenance'
WHERE id = v_aircraft AND status = 'active';
END;
$$;

-- ---------------------------------------------------------------------
-- П2. Процедура: завершення наряду. OUT-параметр — сумарні години.
--     Вимоги: наряд у статусі in_progress, є роботи, немає pending-робіт.
--     Судно повертається в active, якщо інших робочих нарядів немає.
-- ---------------------------------------------------------------------
CREATE PROCEDURE avia_mro.complete_work_order(
    IN p_order_id bigint, OUT p_total_hours numeric
)
    LANGUAGE plpgsql
AS $$
DECLARE
v_aircraft integer;
    v_status   text;
BEGIN
SELECT aircraft_id, status INTO v_aircraft, v_status
FROM avia_mro.work_orders
WHERE id = p_order_id
    FOR UPDATE;

IF NOT FOUND THEN
        RAISE EXCEPTION 'Наряд % не знайдено', p_order_id;
END IF;
    IF v_status <> 'in_progress' THEN
        RAISE EXCEPTION 'Наряд % не можна завершити зі статусу %', p_order_id, v_status;
END IF;
    IF NOT EXISTS (SELECT 1 FROM avia_mro.work_order_tasks WHERE work_order_id = p_order_id) THEN
        RAISE EXCEPTION 'Наряд % не містить жодної роботи', p_order_id;
END IF;
    IF EXISTS (SELECT 1 FROM avia_mro.work_order_tasks
               WHERE work_order_id = p_order_id AND result = 'pending') THEN
        RAISE EXCEPTION 'Наряд % містить незавершені роботи (result = pending)', p_order_id;
END IF;

UPDATE avia_mro.work_orders SET status = 'completed' WHERE id = p_order_id;

SELECT SUM(hours_spent) INTO p_total_hours
FROM avia_mro.work_order_tasks WHERE work_order_id = p_order_id;

IF NOT EXISTS (SELECT 1 FROM avia_mro.work_orders
                   WHERE aircraft_id = v_aircraft AND status = 'in_progress') THEN
UPDATE avia_mro.aircraft SET status = 'active'
WHERE id = v_aircraft AND status = 'in_maintenance';
END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- П3. Процедура: списання запчастини на роботу.
--     SECURITY DEFINER: інженер змінює залишки лише через цю процедуру,
--     прямого UPDATE на spare_parts він не має.
--     Умовний UPDATE (stock_qty >= p_qty) атомарний: при гонці двох
--     сеансів другий повторно перевірить умову після COMMIT першого.
-- ---------------------------------------------------------------------
CREATE PROCEDURE avia_mro.use_spare_part(
    IN p_task_id bigint, IN p_part_id integer, IN p_qty integer
)
    LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = avia_mro, pg_temp
AS $$
DECLARE
v_status text;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Кількість має бути додатною, отримано %', p_qty;
END IF;

SELECT wo.status INTO v_status
FROM work_order_tasks AS t
         JOIN work_orders AS wo ON wo.id = t.work_order_id
WHERE t.id = p_task_id
    FOR SHARE OF wo;

IF NOT FOUND THEN
        RAISE EXCEPTION 'Роботу % не знайдено', p_task_id;
END IF;
    IF v_status <> 'in_progress' THEN
        RAISE EXCEPTION 'Списання можливе лише для наряду у статусі in_progress (зараз %)', v_status;
END IF;

UPDATE spare_parts
SET stock_qty = stock_qty - p_qty
WHERE id = p_part_id AND stock_qty >= p_qty;
IF NOT FOUND THEN
        RAISE EXCEPTION 'Запчастину % не знайдено або недостатній залишок для списання %', p_part_id, p_qty;
END IF;

INSERT INTO part_usage (work_order_task_id, spare_part_id, quantity)
VALUES (p_task_id, p_part_id, p_qty)
    ON CONFLICT (work_order_task_id, spare_part_id)
    DO UPDATE SET quantity = part_usage.quantity + EXCLUDED.quantity;
END;
$$;
