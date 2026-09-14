#!/bin/bash
#
# Exercice 02 : remove duplicates
#
# Remove da tabela 'customers' as linhas duplicadas, incluindo o caso
# em que o mesmo evento aparece de novo com ate 1 segundo de diferenca
# (o servidor de origem as vezes reenvia a mesma instrucao).
#
# Regra: para cada grupo com os mesmos valores em
#   (event_type, product_id, price, user_id, user_session),
# ordenado por event_time, se a diferenca de tempo em relacao
# a linha anterior do mesmo grupo for <= 1 segundo, a linha e descartada.
# Isso cobre tanto duplicatas exatas (diff = 0) quanto quase-duplicatas.

set -e

DB_USER="jcologne"
DB_PASSWORD="mysecretpassword"
DB_NAME="piscineds"
DB_HOST="localhost"
DB_PORT="5432"

export PGPASSWORD="$DB_PASSWORD"

log() {
    echo -e "\n\033[1;34m==>\033[0m $1"
}

PSQL="psql -U $DB_USER -d $DB_NAME -h $DB_HOST -p $DB_PORT"

log "Contagem antes da limpeza:"
$PSQL -c "SELECT COUNT(*) AS total_antes FROM customers;"

log "Removendo duplicatas (exatas e com <= 1s de diferenca)..."

$PSQL -c "
DROP TABLE IF EXISTS customers_clean;

CREATE TABLE customers_clean AS
SELECT event_time, event_type, product_id, price, user_id, user_session
FROM (
    SELECT
        *,
        event_time - LAG(event_time) OVER (
            PARTITION BY event_type, product_id, price, user_id, user_session
            ORDER BY event_time
        ) AS time_diff
    FROM customers
) sub
WHERE time_diff IS NULL OR time_diff > INTERVAL '1 second';

DROP TABLE customers;
ALTER TABLE customers_clean RENAME TO customers;
"

log "Contagem depois da limpeza:"
$PSQL -c "SELECT COUNT(*) AS total_depois FROM customers;"

echo "Concluido."