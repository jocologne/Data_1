#!/bin/bash
#
# Exercice 03 : fusion
#
# Combina a tabela 'customers' (ja sem duplicatas) com 'items',
# usando product_id como chave, via LEFT JOIN para nao perder
# nenhuma linha de customers (mesmo que o produto nao exista em items).
#

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

log "Contagem de customers antes do fusion:"
$PSQL -c "SELECT COUNT(*) AS total_antes FROM customers;"

log "Checando product_id duplicados em items:"
$PSQL -c "
    SELECT COUNT(*) AS product_ids_duplicados FROM (
        SELECT product_id FROM items
        GROUP BY product_id
        HAVING COUNT(*) > 1
    ) dup;
"

log "Deduplicando items por product_id (mantendo a versao com menos campos nulos)..."

$PSQL -c "
DROP TABLE IF EXISTS items_dedup;

CREATE TABLE items_dedup AS
SELECT DISTINCT ON (product_id)
    product_id, category_id, category_code, brand
FROM items
ORDER BY product_id,
         (category_code IS NULL),
         (brand IS NULL);
"

log "Fazendo o LEFT JOIN customers + items_dedup..."

$PSQL -c "
DROP TABLE IF EXISTS customers_fusion;

CREATE TABLE customers_fusion AS
SELECT
    c.event_time,
    c.event_type,
    c.product_id,
    c.price,
    c.user_id,
    c.user_session,
    i.category_id,
    i.category_code,
    i.brand
FROM customers c
LEFT JOIN items_dedup i ON c.product_id = i.product_id;

DROP TABLE customers;
DROP TABLE items_dedup;
ALTER TABLE customers_fusion RENAME TO customers;
"

log "Contagem de customers depois do fusion (deve ser igual a de antes):"
$PSQL -c "SELECT COUNT(*) AS total_depois FROM customers;"

echo "Concluido."