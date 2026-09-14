#!/bin/bash
#
# Exercice 01 : customers table
#
# Une (UNION ALL) todas as tabelas "data_202*_***" existentes no banco
# numa unica tabela chamada "customers".
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

log "Descobrindo tabelas 'data_202*_***' existentes no banco..."

TABLES=$(psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -t -A -c "
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name ~ '^data_202[0-9]_[a-z]+$'
    ORDER BY table_name;
")

if [ -z "$TABLES" ]; then
    echo "Nenhuma tabela 'data_202*_***' encontrada. Rode o setup do Modulo 0 primeiro."
    exit 1
fi

echo "Tabelas encontradas:"
echo "$TABLES" | sed 's/^/  - /'

# Monta a query UNION ALL dinamicamente
UNION_QUERY=""
first=true
while read -r table; do
    [ -z "$table" ] && continue
    if [ "$first" = true ]; then
        UNION_QUERY="SELECT * FROM $table"
        first=false
    else
        UNION_QUERY="$UNION_QUERY UNION ALL SELECT * FROM $table"
    fi
done <<< "$TABLES"

log "Criando a tabela 'customers' a partir da uniao das tabelas acima..."

psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "
    DROP TABLE IF EXISTS customers;
    CREATE TABLE customers AS
    $UNION_QUERY;
"

log "Resultado:"
psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "
    SELECT COUNT(*) AS total_rows FROM customers;
"

echo "Concluido."