#!/bin/bash
#
# setup.sh
#
# Setup completo do Modulo 0 (Piscine Data Science):
#   1. Baixa o subject.zip da intra 42
#   2. Extrai e move as pastas customer/ e items/ para a raiz do projeto
#   3. Sobe o PostgreSQL via Docker Compose (ex00/)
#   4. Cria e popula automaticamente as tabelas data_202*_*** (ex03)
#   5. Cria e popula a tabela items (ex04)
#
# Uso:
#   ./setup.sh
#
# Deve ser executado a partir da raiz do projeto (onde estao as pastas ex00, ex01, etc.)

set -e

# ------------------------------------------------------------------
# Configuracao - ajuste conforme necessario
# ------------------------------------------------------------------
DB_USER="jcologne"
DB_PASSWORD="mysecretpassword"
DB_NAME="piscineds"
DB_HOST="localhost"
DB_PORT="5432"

SUBJECT_URL="https://cdn.intra.42.fr/document/document/50816/subject.zip"
# O script fica em <raiz_do_projeto>/ex00/setup.sh
# WORKDIR = raiz do projeto, independente de onde o script for chamado
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="$WORKDIR/.setup_tmp"
ZIP_FILE="$DOWNLOAD_DIR/subject.zip"
EXTRACT_DIR="$DOWNLOAD_DIR/extracted"

COMPOSE_DIR="$SCRIPT_DIR"        # docker-compose.yml (postgres + pgadmin) vive junto do proprio setup.sh

PGADMIN_EMAIL="jcologne@student.42sp.org.br"
PGADMIN_PASSWORD="mysecretpassword"
PGADMIN_PORT="5050"

# ------------------------------------------------------------------
# Funcoes auxiliares
# ------------------------------------------------------------------
log() {
    echo -e "\n\033[1;34m==>\033[0m $1"
}

error_exit() {
    echo -e "\033[1;31mERRO:\033[0m $1" >&2
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || error_exit "'$1' nao encontrado. Instale antes de continuar."
}

# ------------------------------------------------------------------
# 0. Checagem de dependencias
# ------------------------------------------------------------------
log "Checando dependencias..."
check_command curl
check_command unzip
check_command docker

if ! docker compose version >/dev/null 2>&1; then
    error_exit "'docker compose' (plugin v2) nao encontrado."
fi

if ! command -v psql >/dev/null 2>&1; then
    error_exit "'psql' nao encontrado. Instale com: sudo apt install postgresql-client"
fi

# ------------------------------------------------------------------
# 1. Baixar o subject.zip
# ------------------------------------------------------------------
log "Baixando subject.zip..."
mkdir -p "$DOWNLOAD_DIR"

if [ -f "$ZIP_FILE" ]; then
    echo "Arquivo ja existe em $ZIP_FILE, pulando download."
else
    curl -fSL "$SUBJECT_URL" -o "$ZIP_FILE" \
        || error_exit "Falha ao baixar $SUBJECT_URL"
fi

# ------------------------------------------------------------------
# 2. Extrair e localizar as pastas customer/ e items/
# ------------------------------------------------------------------
log "Extraindo subject.zip..."
mkdir -p "$EXTRACT_DIR"
unzip -oq "$ZIP_FILE" -d "$EXTRACT_DIR"

log "Localizando pastas 'customer' e 'items' (ou 'item') dentro do zip extraido..."

CUSTOMER_SRC=$(find "$EXTRACT_DIR" -type d -iname "customer" | head -n 1)
ITEMS_SRC=$(find "$EXTRACT_DIR" -type d \( -iname "items" -o -iname "item" \) | head -n 1)

[ -n "$CUSTOMER_SRC" ] || error_exit "Pasta 'customer' nao encontrada no zip extraido."
[ -n "$ITEMS_SRC" ] || error_exit "Pasta 'items'/'item' nao encontrada no zip extraido."

echo "customer encontrado em: $CUSTOMER_SRC"
echo "items encontrado em:    $ITEMS_SRC"

# ------------------------------------------------------------------
# 3. Mover para a raiz do projeto
# ------------------------------------------------------------------
log "Movendo pastas para a raiz do projeto..."

if [ -d "$WORKDIR/customer" ]; then
    echo "Pasta 'customer' ja existe na raiz, mantendo a existente (nao sobrescrita)."
else
    mv "$CUSTOMER_SRC" "$WORKDIR/customer"
    echo "-> customer/ movida para a raiz."
fi

if [ -d "$WORKDIR/items" ]; then
    echo "Pasta 'items' ja existe na raiz, mantendo a existente (nao sobrescrita)."
else
    mv "$ITEMS_SRC" "$WORKDIR/items"
    echo "-> items/ movida para a raiz."
fi

rm -rf "$DOWNLOAD_DIR"

# ------------------------------------------------------------------
# 4. Subir o PostgreSQL + pgAdmin via Docker Compose
# ------------------------------------------------------------------
log "Subindo PostgreSQL + pgAdmin via Docker Compose ($COMPOSE_DIR)..."

[ -f "$COMPOSE_DIR/docker-compose.yml" ] \
    || error_exit "docker-compose.yml nao encontrado em $COMPOSE_DIR"

# Evita conflito de nome caso ja exista um container antigo do ex00
docker rm -f piscineds_postgres piscineds_pgadmin >/dev/null 2>&1 || true

(cd "$COMPOSE_DIR" && docker compose up -d)

log "Aguardando o Postgres ficar saudavel..."
ATTEMPTS=0
MAX_ATTEMPTS=30
until docker exec piscineds_postgres pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        error_exit "Postgres nao ficou pronto a tempo."
    fi
    sleep 2
done
echo "Postgres pronto."

# ------------------------------------------------------------------
# 5. Popular tabelas customer (equivalente ao ex03)
# ------------------------------------------------------------------
log "Criando e populando tabelas data_202*_*** a partir de customer/..."

CUSTOMER_SQL="$DOWNLOAD_DIR_UNUSED"
CUSTOMER_SQL="/tmp/setup_customer_tables.sql"
> "$CUSTOMER_SQL"

shopt -s nullglob
csv_files=("$WORKDIR"/customer/*.csv)

if [ ${#csv_files[@]} -eq 0 ]; then
    error_exit "Nenhum CSV encontrado em $WORKDIR/customer/"
fi

for csv in "${csv_files[@]}"; do
    table_name=$(basename "$csv" .csv)
    csv_abs_path=$(realpath "$csv")

    cat >> "$CUSTOMER_SQL" <<EOF
DROP TABLE IF EXISTS $table_name;

CREATE TABLE $table_name (
    event_time     TIMESTAMP,
    event_type     VARCHAR(20),
    product_id     INTEGER,
    price          NUMERIC(10,2),
    user_id        BIGINT,
    user_session   UUID
);

\copy $table_name FROM '$csv_abs_path' DELIMITER ',' CSV HEADER;

EOF
    echo "-> tabela '$table_name' preparada."
done

PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -f "$CUSTOMER_SQL"

# ------------------------------------------------------------------
# 6. Popular tabela items (equivalente ao ex04)
# ------------------------------------------------------------------
log "Criando e populando tabela 'items' a partir de items/..."

ITEMS_CSV=$(find "$WORKDIR/items" -maxdepth 1 -iname "*.csv" | head -n 1)
[ -n "$ITEMS_CSV" ] || error_exit "Nenhum CSV encontrado em $WORKDIR/items/"

ITEMS_CSV_ABS=$(realpath "$ITEMS_CSV")
ITEMS_SQL="/tmp/setup_items_table.sql"

cat > "$ITEMS_SQL" <<EOF
DROP TABLE IF EXISTS items;

CREATE TABLE items (
    product_id      INTEGER,
    category_id     BIGINT,
    category_code   VARCHAR(100),
    brand           VARCHAR(50)
);

\copy items FROM '$ITEMS_CSV_ABS' DELIMITER ',' CSV HEADER;
EOF

PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -f "$ITEMS_SQL"

# ------------------------------------------------------------------
# 7. Resumo final
# ------------------------------------------------------------------
log "Resumo das tabelas criadas:"
PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "\dt"

# ------------------------------------------------------------------
# 8. Checar pgAdmin
# ------------------------------------------------------------------
log "Verificando pgAdmin..."

ATTEMPTS=0
MAX_ATTEMPTS=15
until curl -sf "http://127.0.0.1:$PGADMIN_PORT" -o /dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "Aviso: pgAdmin ainda nao respondeu em http://127.0.0.1:$PGADMIN_PORT (pode levar mais alguns segundos)."
        break
    fi
    sleep 2
done

log "Setup concluido com sucesso!"
echo ""
echo "Postgres  -> psql -U $DB_USER -d $DB_NAME -h $DB_HOST -W"
echo "pgAdmin   -> http://127.0.0.1:$PGADMIN_PORT"
echo "  login:  $PGADMIN_EMAIL"
echo "  senha:  $PGADMIN_PASSWORD"
echo ""
echo "No pgAdmin, registre o servidor com:"
echo "  Host name/address: postgres   (nome do servico no docker-compose, nao localhost)"
echo "  Port: $DB_PORT"
echo "  Maintenance database: $DB_NAME"
echo "  Username: $DB_USER"
echo "  Password: $DB_PASSWORD"