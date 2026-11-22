#!/usr/bin/env bash
# =====================================================================
# experiments/03_backup_restore.sh — перевірка створення логічного
# дампу (pg_dump) та відновлення у чисту БД (pg_restore) (п. 5.10, с. 21).
# =====================================================================
set -euo pipefail

CONTAINER="avia_mro_postgres"
USER="postgres"
SRC_DB="avia_mro_db"
RESTORE_DB="avia_mro_restore"
DUMP_FILE="/tmp/avia_mro.dump"

echo "== 1. Створення бінарного дампу бази ${SRC_DB} =="
docker exec "$CONTAINER" pg_dump -U "$USER" -d "$SRC_DB" -Fc -f "$DUMP_FILE"

echo "== 2. Перестворення чистої цільової бази ${RESTORE_DB} =="
docker exec "$CONTAINER" dropdb -U "$USER" --if-exists "$RESTORE_DB"
docker exec "$CONTAINER" createdb -U "$USER" "$RESTORE_DB"

echo "== 3. Відновлення з дампу у ${RESTORE_DB} =="
docker exec "$CONTAINER" pg_restore -U "$USER" --exit-on-error --no-owner -d "$RESTORE_DB" "$DUMP_FILE"

echo "== 4. Контрольна перевірка об'єктів та кількості записів =="
docker exec "$CONTAINER" psql -U "$USER" -d "$RESTORE_DB" -c "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'avia_mro'
ORDER BY table_name;

SELECT (SELECT COUNT(*) FROM avia_mro.aircraft)         AS aircraft_cnt,
       (SELECT COUNT(*) FROM avia_mro.work_orders)      AS work_orders_cnt,
       (SELECT COUNT(*) FROM avia_mro.work_order_tasks) AS tasks_cnt,
       (SELECT COUNT(*) FROM avia_mro.defects)          AS defects_cnt;
"