-- =====================================================================
-- 06_roles.sql — ролі та права доступу (принцип найменших привілеїв)
-- Ролі створюються без LOGIN і без паролів: у реальному середовищі
-- користувачам видають членство в цих ролях (GRANT mro_engineer TO alice).
-- Ролі є об'єктами кластера, тому створення зроблено ідемпотентним.
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mro_engineer') THEN
CREATE ROLE mro_engineer NOLOGIN;
END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mro_analyst') THEN
CREATE ROLE mro_analyst NOLOGIN;
END IF;
END
$$;

GRANT USAGE ON SCHEMA avia_mro TO mro_engineer, mro_analyst;

-- Функції та процедури за замовчуванням доступні PUBLIC — забираємо
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA avia_mro FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Аналітик: лише читання (таблиці, представлення, журнал аудиту)
-- ---------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA avia_mro TO mro_analyst;
GRANT EXECUTE ON FUNCTION avia_mro.aircraft_maintenance_hours(integer, date, date),
                          avia_mro.component_resource_left(integer)
      TO mro_analyst;

-- ---------------------------------------------------------------------
-- Інженер: читає довідники й операційні дані (крім журналу аудиту),
-- веде наряди й роботи, фіксує дефекти. Запчастини списує лише процедурою.
-- ---------------------------------------------------------------------
GRANT SELECT ON avia_mro.aircraft_types, avia_mro.aircraft, avia_mro.component_types,
    avia_mro.components, avia_mro.employees, avia_mro.maintenance_types,
    avia_mro.work_orders, avia_mro.work_order_tasks, avia_mro.defects,
    avia_mro.spare_parts, avia_mro.part_usage,
    avia_mro.v_aircraft_maintenance_summary,
    avia_mro.v_components_resource,
    avia_mro.v_open_defects
    TO mro_engineer;

GRANT INSERT, UPDATE ON avia_mro.work_orders, avia_mro.work_order_tasks TO mro_engineer;
GRANT INSERT ON avia_mro.defects TO mro_engineer;
GRANT UPDATE (status, resolved_at) ON avia_mro.defects TO mro_engineer;
GRANT UPDATE (hours_since_overhaul, status) ON avia_mro.components TO mro_engineer;
GRANT UPDATE (status) ON avia_mro.aircraft TO mro_engineer;
GRANT USAGE ON SEQUENCE avia_mro.work_order_number_seq TO mro_engineer;

GRANT EXECUTE ON FUNCTION avia_mro.aircraft_maintenance_hours(integer, date, date),
                          avia_mro.component_resource_left(integer),
                          avia_mro.create_work_order(integer, integer, date)
      TO mro_engineer;
GRANT EXECUTE ON PROCEDURE avia_mro.start_work_order(bigint),
                           avia_mro.complete_work_order(bigint, numeric),
                           avia_mro.use_spare_part(bigint, integer, integer)
      TO mro_engineer;
