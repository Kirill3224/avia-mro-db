-- =====================================================================
-- 02_seed.sql — тестові дані (виконується до створення тригерів,
-- тому журнал аудиту після завантаження порожній)
-- =====================================================================
INSERT INTO avia_mro.aircraft_types (type_code, manufacturer, model) VALUES
                                                                         ('A320', 'Airbus',  'A320-214'),
                                                                         ('B737', 'Boeing',  '737-800'),
                                                                         ('E190', 'Embraer', 'E190-100');

INSERT INTO avia_mro.aircraft (tail_number, aircraft_type_id, serial_number,
                               manufactured_year, total_flight_hours, status)
SELECT v.tail, t.id, v.sn, v.yr, v.hrs, v.st
FROM (VALUES
          ('UR-AAA', 'A320', '4521',     2012, 38450.5, 'active'),
          ('UR-AAB', 'A320', '4873',     2014, 31220.0, 'in_maintenance'),
          ('UR-BBA', 'B737', '30112',    2010, 45890.3, 'active'),
          ('UR-BBB', 'B737', '33545',    2016, 22110.8, 'active'),
          ('UR-EEA', 'E190', '19000321', 2013, 29760.2, 'grounded'),
          ('UR-EEB', 'E190', '19000455', 2018, 14320.0, 'active')
     ) AS v(tail, tcode, sn, yr, hrs, st)
         JOIN avia_mro.aircraft_types t ON t.type_code = v.tcode;

INSERT INTO avia_mro.component_types (part_number, name, category, overhaul_interval_hours) VALUES
                                                                                                ('CFM56-5B',   'Двигун CFM56-5B',                    'engine',       20000),
                                                                                                ('LG-MAIN-01', 'Основна стійка шасі',                'landing_gear', 15000),
                                                                                                ('HYD-PUMP-7', 'Гідронасос',                         'hydraulics',    8000),
                                                                                                ('AVN-FMC-3',  'Комп’ютер керування польотом (FMC)', 'avionics',     12000),
                                                                                                ('GEN-90KVA',  'Генератор 90 kVA',                   'electrical',   10000);

INSERT INTO avia_mro.components (component_type_id, serial_number, aircraft_id,
                                 installed_on, hours_since_overhaul, status)
SELECT ct.id, v.sn, a.id, v.inst, v.hrs, v.st
FROM (VALUES
          ('CFM56-5B',   'ENG-1001', 'UR-AAA', DATE '2023-03-10', 17500.0, 'serviceable'),
          ('CFM56-5B',   'ENG-1002', 'UR-AAA', DATE '2023-03-10', 18400.0, 'serviceable'),
          ('CFM56-5B',   'ENG-1003', 'UR-AAB', DATE '2024-05-20',  9000.0, 'serviceable'),
          ('CFM56-5B',   'ENG-1004', 'UR-BBA', DATE '2022-11-01', 19200.0, 'serviceable'),
          ('CFM56-5B',   'ENG-1005', NULL,     NULL::date,            0.0, 'serviceable'),
          ('LG-MAIN-01', 'LG-2001',  'UR-AAA', DATE '2022-01-15',  6000.0, 'serviceable'),
          ('LG-MAIN-01', 'LG-2002',  'UR-BBA', DATE '2021-08-30', 14200.0, 'serviceable'),
          ('HYD-PUMP-7', 'HP-3001',  'UR-AAB', DATE '2025-02-12',  3100.0, 'serviceable'),
          ('HYD-PUMP-7', 'HP-3002',  'UR-BBB', DATE '2025-06-01',  1200.0, 'serviceable'),
          ('HYD-PUMP-7', 'HP-3003',  NULL,     NULL::date,         7900.0, 'under_repair'),
          ('AVN-FMC-3',  'FMC-4001', 'UR-AAA', DATE '2024-09-09',  4200.0, 'serviceable'),
          ('AVN-FMC-3',  'FMC-4002', 'UR-EEA', DATE '2023-01-20', 11000.0, 'serviceable'),
          ('GEN-90KVA',  'GEN-5001', 'UR-BBB', DATE '2024-03-03',  7600.0, 'serviceable'),
          ('GEN-90KVA',  'GEN-5002', 'UR-EEA', DATE '2020-12-12',  9900.0, 'under_repair')
     ) AS v(pn, sn, tail, inst, hrs, st)
         JOIN avia_mro.component_types ct ON ct.part_number = v.pn
         LEFT JOIN avia_mro.aircraft a ON a.tail_number = v.tail;

INSERT INTO avia_mro.employees (personnel_number, full_name, qualification) VALUES
                                                                                ('P001', 'Коваленко Андрій Петрович',  'engineer'),
                                                                                ('P002', 'Шевченко Олена Іванівна',    'inspector'),
                                                                                ('P003', 'Мельник Дмитро Сергійович',  'technician'),
                                                                                ('P004', 'Бондаренко Ірина Василівна', 'technician'),
                                                                                ('P005', 'Ткаченко Максим Олегович',   'engineer'),
                                                                                ('P006', 'Лисенко Наталія Андріївна',  'technician');

INSERT INTO avia_mro.maintenance_types (code, name, interval_days, standard_hours) VALUES
                                                                                       ('A-CHECK',  'Оперативне ТО (A-check)',     60,   40),
                                                                                       ('C-CHECK',  'Базове ТО (C-check)',        730,  600),
                                                                                       ('ENG-INSP', 'Бороскопічний огляд двигуна', 180,   24),
                                                                                       ('UNSCHED',  'Позапланове усунення дефекту', NULL,  8);

INSERT INTO avia_mro.work_orders (order_number, aircraft_id, maintenance_type_id, status,
                                  planned_date, started_at, completed_at)
SELECT v.num, a.id, m.id, v.st, v.pl, v.s_at, v.c_at
FROM (VALUES
          ('WO-2026-0001', 'UR-AAA', 'A-CHECK',  'completed',   DATE '2026-07-10', TIMESTAMPTZ '2026-07-10 08:00+03', TIMESTAMPTZ '2026-07-11 17:00+03'),
          ('WO-2026-0002', 'UR-AAA', 'ENG-INSP', 'completed',   DATE '2026-08-20', TIMESTAMPTZ '2026-08-20 09:00+03', TIMESTAMPTZ '2026-08-20 18:00+03'),
          ('WO-2026-0003', 'UR-AAB', 'C-CHECK',  'in_progress', DATE '2026-10-28', TIMESTAMPTZ '2026-10-28 08:00+03', NULL::timestamptz),
          ('WO-2026-0004', 'UR-BBA', 'A-CHECK',  'completed',   DATE '2026-09-05', TIMESTAMPTZ '2026-09-05 08:00+03', TIMESTAMPTZ '2026-09-06 16:00+03'),
          ('WO-2026-0005', 'UR-BBA', 'UNSCHED',  'completed',   DATE '2026-10-02', TIMESTAMPTZ '2026-10-02 10:00+03', TIMESTAMPTZ '2026-10-03 12:00+03'),
          ('WO-2026-0006', 'UR-BBB', 'A-CHECK',  'completed',   DATE '2026-09-15', TIMESTAMPTZ '2026-09-15 08:00+03', TIMESTAMPTZ '2026-09-16 15:00+03'),
          ('WO-2026-0007', 'UR-EEA', 'UNSCHED',  'in_progress', DATE '2026-11-03', TIMESTAMPTZ '2026-11-03 09:00+02', NULL::timestamptz),
          ('WO-2026-0008', 'UR-AAA', 'A-CHECK',  'planned',     DATE '2026-12-05', NULL::timestamptz, NULL::timestamptz),
          ('WO-2026-0009', 'UR-BBB', 'ENG-INSP', 'cancelled',   DATE '2026-10-10', NULL::timestamptz, NULL::timestamptz),
          ('WO-2026-0010', 'UR-BBA', 'A-CHECK',  'planned',     DATE '2026-12-10', NULL::timestamptz, NULL::timestamptz)
     ) AS v(num, tail, mcode, st, pl, s_at, c_at)
         JOIN avia_mro.aircraft a ON a.tail_number = v.tail
         JOIN avia_mro.maintenance_types m ON m.code = v.mcode;

INSERT INTO avia_mro.work_order_tasks (work_order_id, component_id, employee_id,
                                       description, hours_spent, result)
SELECT wo.id, c.id, e.id, v.descr, v.hrs, v.res
FROM (VALUES
          ('WO-2026-0001', NULL,       'P003', 'Загальний огляд планера',    12.0, 'ok'),
          ('WO-2026-0001', 'ENG-1001', 'P001', 'Огляд двигуна №1',            6.5, 'ok'),
          ('WO-2026-0001', 'ENG-1002', 'P001', 'Огляд двигуна №2',            6.5, 'defect'),
          ('WO-2026-0001', 'LG-2001',  'P004', 'Змащення шасі',               4.0, 'ok'),
          ('WO-2026-0001', 'FMC-4001', 'P005', 'Перевірка FMC',               3.0, 'ok'),
          ('WO-2026-0002', 'ENG-1001', 'P001', 'Бороскопія двигуна №1',       8.0, 'ok'),
          ('WO-2026-0002', 'ENG-1002', 'P005', 'Бороскопія двигуна №2',       8.5, 'defect'),
          ('WO-2026-0003', NULL,       'P004', 'Розбирання панелей',         22.0, 'ok'),
          ('WO-2026-0003', 'HP-3001',  'P003', 'Перевірка гідросистеми',     10.0, 'pending'),
          ('WO-2026-0004', NULL,       'P004', 'Огляд планера',              11.0, 'ok'),
          ('WO-2026-0004', 'LG-2002',  'P003', 'Огляд шасі',                  5.5, 'defect'),
          ('WO-2026-0004', 'ENG-1004', 'P001', 'Огляд двигуна',               7.0, 'ok'),
          ('WO-2026-0005', 'LG-2002',  'P003', 'Заміна гальмівного вузла',    9.0, 'ok'),
          ('WO-2026-0005', NULL,       'P002', 'Інспекція після усунення',    2.5, 'ok'),
          ('WO-2026-0006', NULL,       'P004', 'Огляд планера',              10.0, 'ok'),
          ('WO-2026-0006', 'GEN-5001', 'P005', 'Перевірка генератора',        4.5, 'ok'),
          ('WO-2026-0006', 'HP-3002',  'P003', 'Перевірка гідронасоса',       2.0, 'ok'),
          ('WO-2026-0007', 'GEN-5002', 'P005', 'Діагностика генератора',      6.0, 'defect'),
          ('WO-2026-0007', 'FMC-4002', 'P001', 'Діагностика FMC',             4.0, 'pending')
     ) AS v(wo_num, comp_sn, pers, descr, hrs, res)
         JOIN avia_mro.work_orders wo ON wo.order_number = v.wo_num
         LEFT JOIN avia_mro.components c ON c.serial_number = v.comp_sn
         JOIN avia_mro.employees e ON e.personnel_number = v.pers;

INSERT INTO avia_mro.defects (aircraft_id, component_id, found_at, severity,
                              description, status, resolved_at)
SELECT a.id, c.id, v.f_at, v.sev, v.descr, v.st, v.r_at
FROM (VALUES
          ('UR-AAA', 'ENG-1002', TIMESTAMPTZ '2026-07-10 14:00+03', 'major',    'Знос лопаток турбіни',       'resolved', TIMESTAMPTZ '2026-07-11 16:00+03'),
          ('UR-AAA', 'ENG-1002', TIMESTAMPTZ '2026-08-20 15:00+03', 'major',    'Підвищена вібрація двигуна', 'open',     NULL::timestamptz),
          ('UR-BBA', 'LG-2002',  TIMESTAMPTZ '2026-09-05 12:00+03', 'critical', 'Знос гальмівного вузла',     'resolved', TIMESTAMPTZ '2026-10-03 11:00+03'),
          ('UR-EEA', 'GEN-5002', TIMESTAMPTZ '2026-11-03 10:00+02', 'critical', 'Втрата напруги генератора',  'open',     NULL::timestamptz),
          ('UR-EEA', 'FMC-4002', TIMESTAMPTZ '2026-11-03 11:00+02', 'minor',    'Періодичні помилки FMC',     'open',     NULL::timestamptz),
          ('UR-BBB', NULL,       TIMESTAMPTZ '2026-09-15 13:00+03', 'minor',    'Подряпина обшивки',          'resolved', TIMESTAMPTZ '2026-09-16 10:00+03')
     ) AS v(tail, comp_sn, f_at, sev, descr, st, r_at)
         JOIN avia_mro.aircraft a ON a.tail_number = v.tail
         LEFT JOIN avia_mro.components c ON c.serial_number = v.comp_sn;

INSERT INTO avia_mro.spare_parts (part_number, name, stock_qty, min_qty) VALUES
                                                                             ('SP-FILTER-01', 'Масляний фільтр',            25, 10),
                                                                             ('SP-SEAL-22',   'Ущільнювач гідросистеми',     8, 10),
                                                                             ('SP-BRK-05',    'Гальмівний вузол',            3,  2),
                                                                             ('SP-BLT-10',    'Болт кріплення (комплект)', 120, 50),
                                                                             ('SP-LAMP-03',   'Сигнальна лампа',             4,  5);

INSERT INTO avia_mro.part_usage (work_order_task_id, spare_part_id, quantity)
SELECT t.id, sp.id, v.qty
FROM (VALUES
          ('WO-2026-0001', 'Огляд двигуна №1',         'SP-FILTER-01',  2),
          ('WO-2026-0001', 'Огляд двигуна №2',         'SP-FILTER-01',  2),
          ('WO-2026-0004', 'Огляд шасі',               'SP-SEAL-22',    3),
          ('WO-2026-0006', 'Перевірка гідронасоса',    'SP-SEAL-22',    1),
          ('WO-2026-0003', 'Перевірка гідросистеми',   'SP-BLT-10',    20),
          ('WO-2026-0005', 'Заміна гальмівного вузла', 'SP-BRK-05',     1),
          ('WO-2026-0007', 'Діагностика генератора',   'SP-LAMP-03',    1)
     ) AS v(wo_num, descr, pn, qty)
         JOIN avia_mro.work_orders wo ON wo.order_number = v.wo_num
         JOIN avia_mro.work_order_tasks t ON t.work_order_id = wo.id AND t.description = v.descr
         JOIN avia_mro.spare_parts sp ON sp.part_number = v.pn;
