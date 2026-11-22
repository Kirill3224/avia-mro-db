-- =====================================================================
-- 05_triggers.sql — тригери
-- =====================================================================

-- ---------------------------------------------------------------------
-- Т1 (BEFORE): допустимі переходи статусу наряду (BR06)
--     planned     -> in_progress | cancelled
--     in_progress -> completed   | cancelled
--     completed, cancelled — кінцеві статуси.
--     Такі правила не виразити стандартним CHECK, бо потрібне старе значення.
--     Заодно проставляє started_at / completed_at.
-- ---------------------------------------------------------------------
CREATE FUNCTION avia_mro.trg_work_orders_check_status()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT (   (OLD.status = 'planned'     AND NEW.status IN ('in_progress', 'cancelled'))
            OR (OLD.status = 'in_progress' AND NEW.status IN ('completed', 'cancelled'))) THEN
        RAISE EXCEPTION 'Недопустимий перехід статусу наряду %: % -> %',
                        OLD.order_number, OLD.status, NEW.status;
END IF;

    IF NEW.status = 'in_progress' THEN
        NEW.started_at := COALESCE(NEW.started_at, clock_timestamp());
    ELSIF NEW.status = 'completed' THEN
        NEW.completed_at := clock_timestamp();
END IF;
RETURN NEW;
END;
$$;

CREATE TRIGGER work_orders_check_status
    BEFORE UPDATE OF status ON avia_mro.work_orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION avia_mro.trg_work_orders_check_status();

-- ---------------------------------------------------------------------
-- Т2 (AFTER): аудит змін статусу наряду.
--     SECURITY DEFINER: ролі не мають прямого INSERT у audit_log.
--     Автор зміни — session_user (реальний логін), бо current_user
--     всередині SECURITY DEFINER-функції дорівнює власнику.
-- ---------------------------------------------------------------------
CREATE FUNCTION avia_mro.trg_work_orders_audit()
    RETURNS trigger
    LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = avia_mro, pg_temp
AS $$
BEGIN
INSERT INTO audit_log (table_name, record_id, field_name, old_value, new_value)
VALUES ('work_orders', NEW.id, 'status', OLD.status, NEW.status);
RETURN NEW;
END;
$$;

CREATE TRIGGER work_orders_audit
    AFTER UPDATE OF status ON avia_mro.work_orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION avia_mro.trg_work_orders_audit();

-- ---------------------------------------------------------------------
-- Т3 (BEFORE): не можна додавати/переносити роботи в завершений або
--     скасований наряд (BR09). FOR SHARE блокує рядок наряду, тому
--     паралельне завершення наряду не «проскочить» між перевіркою і вставкою.
-- ---------------------------------------------------------------------
CREATE FUNCTION avia_mro.trg_tasks_check_order_open()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
v_status text;
BEGIN
SELECT status INTO v_status
FROM avia_mro.work_orders
WHERE id = NEW.work_order_id
    FOR SHARE;

IF v_status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Наряд (id=%) має статус %, додавати роботи заборонено',
                        NEW.work_order_id, v_status;
END IF;
RETURN NEW;
END;
$$;

CREATE TRIGGER tasks_check_order_open
    BEFORE INSERT OR UPDATE OF work_order_id ON avia_mro.work_order_tasks
    FOR EACH ROW
    EXECUTE FUNCTION avia_mro.trg_tasks_check_order_open();
