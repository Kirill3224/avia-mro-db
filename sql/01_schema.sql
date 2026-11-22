-- =====================================================================
-- 01_schema.sql — структура бази даних «Облік ТО авіаційного обладнання»
-- =====================================================================
CREATE SCHEMA avia_mro;

-- Довідник типів повітряних суден
CREATE TABLE avia_mro.aircraft_types (
                                         id           integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                         type_code    text NOT NULL UNIQUE,
                                         manufacturer text NOT NULL CHECK (btrim(manufacturer) <> ''),
                                         model        text NOT NULL CHECK (btrim(model) <> '')
);

-- Повітряні судна
CREATE TABLE avia_mro.aircraft (
                                   id                 integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                   tail_number        text NOT NULL UNIQUE
                                       CHECK (tail_number ~ '^[A-Z]{2}-[A-Z0-9]{3,5}$'),       -- BR01
    aircraft_type_id   integer NOT NULL
                       REFERENCES avia_mro.aircraft_types(id) ON DELETE RESTRICT,
    serial_number      text NOT NULL,
    manufactured_year  smallint NOT NULL CHECK (manufactured_year BETWEEN 1950 AND 2100),
    total_flight_hours numeric(10,1) NOT NULL DEFAULT 0
                       CHECK (total_flight_hours >= 0),                       -- BR02
    status             text NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active', 'in_maintenance', 'grounded')),
    CONSTRAINT aircraft_type_serial_uq UNIQUE (aircraft_type_id, serial_number)
);

-- Довідник типів агрегатів (ресурс між ремонтами)
CREATE TABLE avia_mro.component_types (
                                          id                      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                          part_number             text NOT NULL UNIQUE,
                                          name                    text NOT NULL CHECK (btrim(name) <> ''),
                                          category                text NOT NULL
                                              CHECK (category IN ('engine', 'avionics', 'landing_gear',
                                                                  'hydraulics', 'electrical')),
                                          overhaul_interval_hours numeric(8,1) NOT NULL CHECK (overhaul_interval_hours > 0)
);

-- Конкретні агрегати (серійні екземпляри). aircraft_id IS NULL — агрегат на складі
CREATE TABLE avia_mro.components (
                                     id                   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                     component_type_id    integer NOT NULL
                                         REFERENCES avia_mro.component_types(id) ON DELETE RESTRICT,
                                     serial_number        text NOT NULL,
                                     aircraft_id          integer
                                         REFERENCES avia_mro.aircraft(id) ON DELETE RESTRICT,
                                     installed_on         date,
                                     hours_since_overhaul numeric(8,1) NOT NULL DEFAULT 0
                                         CHECK (hours_since_overhaul >= 0),
                                     status               text NOT NULL DEFAULT 'serviceable'
                                         CHECK (status IN ('serviceable', 'under_repair', 'scrapped')),
                                     CONSTRAINT components_type_serial_uq UNIQUE (component_type_id, serial_number),
    -- BR08: дата встановлення є тоді й лише тоді, коли агрегат встановлено на судно
                                     CONSTRAINT components_install_consistent
                                         CHECK ((aircraft_id IS NULL) = (installed_on IS NULL))
);

-- Працівники
CREATE TABLE avia_mro.employees (
                                    id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                    personnel_number text NOT NULL UNIQUE,
                                    full_name        text NOT NULL CHECK (btrim(full_name) <> ''),
                                    qualification    text NOT NULL
                                        CHECK (qualification IN ('technician', 'engineer', 'inspector')),
                                    active           boolean NOT NULL DEFAULT true
);

-- Довідник видів технічного обслуговування
CREATE TABLE avia_mro.maintenance_types (
                                            id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                            code           text NOT NULL UNIQUE,
                                            name           text NOT NULL CHECK (btrim(name) <> ''),
                                            interval_days  integer CHECK (interval_days > 0),   -- NULL: позапланове ТО
                                            standard_hours numeric(6,1) NOT NULL CHECK (standard_hours > 0)
);

-- Нумерація нарядів
CREATE SEQUENCE avia_mro.work_order_number_seq START 100;

-- Наряди на технічне обслуговування
CREATE TABLE avia_mro.work_orders (
                                      id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                      order_number        text NOT NULL UNIQUE,
                                      aircraft_id         integer NOT NULL
                                          REFERENCES avia_mro.aircraft(id) ON DELETE RESTRICT,   -- BR03/BR04
                                      maintenance_type_id integer NOT NULL
                                          REFERENCES avia_mro.maintenance_types(id) ON DELETE RESTRICT,
                                      status              text NOT NULL DEFAULT 'planned'
                                          CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
                                      planned_date        date NOT NULL,
                                      started_at          timestamptz,
                                      completed_at        timestamptz,
                                      created_at          timestamptz NOT NULL DEFAULT now(),
    -- BR05: завершення не раніше початку
                                      CONSTRAINT wo_time_order CHECK (completed_at IS NULL OR started_at IS NULL
                                          OR completed_at >= started_at),
    -- BR06a: completed_at заповнено тоді й лише тоді, коли наряд завершено
                                      CONSTRAINT wo_completed_consistent CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

-- Роботи в межах наряду
CREATE TABLE avia_mro.work_order_tasks (
                                           id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                           work_order_id bigint NOT NULL
                                               REFERENCES avia_mro.work_orders(id) ON DELETE RESTRICT,
                                           component_id  integer
                                               REFERENCES avia_mro.components(id) ON DELETE RESTRICT,
                                           employee_id   integer NOT NULL
                                               REFERENCES avia_mro.employees(id) ON DELETE RESTRICT,
                                           description   text NOT NULL CHECK (btrim(description) <> ''),
                                           hours_spent   numeric(5,2) NOT NULL
                                               CHECK (hours_spent > 0 AND hours_spent <= 24),               -- BR10
                                           result        text NOT NULL DEFAULT 'pending'
                                               CHECK (result IN ('ok', 'defect', 'pending'))
);

-- Виявлені дефекти
CREATE TABLE avia_mro.defects (
                                  id           integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                  aircraft_id  integer NOT NULL
                                      REFERENCES avia_mro.aircraft(id) ON DELETE RESTRICT,
                                  component_id integer
                                      REFERENCES avia_mro.components(id) ON DELETE RESTRICT,
                                  found_at     timestamptz NOT NULL,
                                  severity     text NOT NULL CHECK (severity IN ('minor', 'major', 'critical')),
                                  description  text NOT NULL CHECK (btrim(description) <> ''),
                                  status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
                                  resolved_at  timestamptz,
                                  CONSTRAINT defects_resolved_consistent             -- BR11
                                      CHECK ((status = 'resolved') = (resolved_at IS NOT NULL)),
                                  CONSTRAINT defects_time_order
                                      CHECK (resolved_at IS NULL OR resolved_at >= found_at)
);

-- Запасні частини
CREATE TABLE avia_mro.spare_parts (
                                      id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                      part_number text NOT NULL UNIQUE,
                                      name        text NOT NULL CHECK (btrim(name) <> ''),
                                      stock_qty   integer NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),            -- BR07
                                      min_qty     integer NOT NULL DEFAULT 0 CHECK (min_qty >= 0)
);

-- Використання запчастин у роботах (зв'язок N:M)
CREATE TABLE avia_mro.part_usage (
                                     work_order_task_id bigint NOT NULL
                                         REFERENCES avia_mro.work_order_tasks(id) ON DELETE RESTRICT,
                                     spare_part_id      integer NOT NULL
                                         REFERENCES avia_mro.spare_parts(id) ON DELETE RESTRICT,
                                     quantity           integer NOT NULL CHECK (quantity > 0),
                                     PRIMARY KEY (work_order_task_id, spare_part_id)
);

-- Журнал аудиту змін статусу
CREATE TABLE avia_mro.audit_log (
                                    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                    table_name text NOT NULL,
                                    record_id  bigint NOT NULL,
                                    field_name text NOT NULL,
                                    old_value  text,
                                    new_value  text,
                                    changed_by text NOT NULL DEFAULT session_user,
                                    changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Індекси на зовнішні ключі (PostgreSQL не створює їх автоматично)
CREATE INDEX work_orders_aircraft_idx ON avia_mro.work_orders (aircraft_id);
CREATE INDEX work_orders_status_idx   ON avia_mro.work_orders (status);
CREATE INDEX tasks_work_order_idx     ON avia_mro.work_order_tasks (work_order_id);
CREATE INDEX tasks_employee_idx       ON avia_mro.work_order_tasks (employee_id);
CREATE INDEX components_aircraft_idx  ON avia_mro.components (aircraft_id);
CREATE INDEX defects_aircraft_idx     ON avia_mro.defects (aircraft_id);
-- Частковий індекс: відкриті дефекти становлять малу частку записів
CREATE INDEX defects_open_idx         ON avia_mro.defects (aircraft_id) WHERE status = 'open';
CREATE INDEX audit_log_record_idx     ON avia_mro.audit_log (table_name, record_id);

-- Призначення таблиць (використовується генератором словника даних)
COMMENT ON TABLE avia_mro.aircraft_types     IS 'Довідник типів повітряних суден';
COMMENT ON TABLE avia_mro.aircraft           IS 'Повітряні судна парку';
COMMENT ON TABLE avia_mro.component_types    IS 'Довідник типів агрегатів із міжремонтним ресурсом';
COMMENT ON TABLE avia_mro.components         IS 'Серійні агрегати (встановлені на судно або на складі)';
COMMENT ON TABLE avia_mro.employees          IS 'Працівники, які виконують технічне обслуговування';
COMMENT ON TABLE avia_mro.maintenance_types  IS 'Довідник видів технічного обслуговування';
COMMENT ON TABLE avia_mro.work_orders        IS 'Наряди на технічне обслуговування';
COMMENT ON TABLE avia_mro.work_order_tasks   IS 'Роботи в межах наряду з витраченими годинами';
COMMENT ON TABLE avia_mro.defects            IS 'Виявлені дефекти суден і агрегатів';
COMMENT ON TABLE avia_mro.spare_parts        IS 'Склад запасних частин';
COMMENT ON TABLE avia_mro.part_usage         IS 'Використання запчастин у роботах (зв''язок N:M)';
COMMENT ON TABLE avia_mro.audit_log          IS 'Журнал аудиту змін статусу нарядів';
