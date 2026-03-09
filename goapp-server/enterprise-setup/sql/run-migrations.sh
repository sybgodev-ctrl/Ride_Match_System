#!/bin/bash
# ============================================================
# GoApp Enterprise Schema Migration Runner
# Executes all numbered migration files in lexical order
# ============================================================

set -e

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-goapp_enterprise}"
DB_USER="${DB_USER:-goapp}"
DB_PASS="${DB_PASS:-goapp}"

export PGPASSWORD="$DB_PASS"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo "GoApp Enterprise Schema Migration"
echo "============================================"
echo "Host: $DB_HOST:$DB_PORT"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""

if command -v psql >/dev/null 2>&1; then
    RUN_MODE="local_psql"
    echo "Mode: local psql"
else
    RUN_MODE="docker_psql"
    echo "Mode: docker compose exec postgres psql"
fi
echo ""

run_psql_file() {
    local sql_file="$1"
    if [ "$RUN_MODE" = "local_psql" ]; then
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$sql_file"
    else
        docker compose -f "$SETUP_DIR/docker-compose.yml" exec -T postgres \
            psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f /dev/stdin < "$sql_file"
    fi
}

run_psql_cmd() {
    local sql_cmd="$1"
    if [ "$RUN_MODE" = "local_psql" ]; then
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "$sql_cmd"
    else
        docker compose -f "$SETUP_DIR/docker-compose.yml" exec -T postgres \
            psql -U "$DB_USER" -d "$DB_NAME" -t -c "$sql_cmd"
    fi
}

# Discover migration files dynamically and execute in lexical order.
MIGRATIONS=()
for f in "$SCRIPT_DIR"/[0-9][0-9][0-9]_*.sql; do
    [ -e "$f" ] || continue
    MIGRATIONS+=("$(basename "$f")")
done

if [ "${#MIGRATIONS[@]}" -eq 0 ]; then
    echo "No migration files found in $SCRIPT_DIR"
    exit 1
fi

IFS=$'\n' MIGRATIONS=($(printf "%s\n" "${MIGRATIONS[@]}" | sort))
unset IFS

MAX_PREFIX=$(printf "%s\n" "${MIGRATIONS[@]}" | sed -E 's/^([0-9]{3})_.*/\1/' | sort -n | tail -n 1)
MAX_PREFIX_NUM=$((10#$MAX_PREFIX))

MISSING_PREFIXES=()
for n in $(seq 1 "$MAX_PREFIX_NUM"); do
    prefix=$(printf "%03d" "$n")
    found=0
    for file in "${MIGRATIONS[@]}"; do
        case "$file" in
            "${prefix}"_*) found=1; break ;;
        esac
    done
    if [ "$found" -eq 0 ]; then
        MISSING_PREFIXES+=("$prefix")
    fi
done

if [ "${#MISSING_PREFIXES[@]}" -gt 0 ]; then
    echo "Missing expected migration prefixes: ${MISSING_PREFIXES[*]}"
    exit 1
fi

TOTAL=${#MIGRATIONS[@]}
SUCCESS=0
FAILED=0

for i in "${!MIGRATIONS[@]}"; do
    FILE="${MIGRATIONS[$i]}"
    NUM=$((i + 1))
    echo "[$NUM/$TOTAL] Running: $FILE"

    if run_psql_file "$SCRIPT_DIR/$FILE" > /dev/null 2>&1; then
        echo "  ✓ Success"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "  ✗ FAILED"
        FAILED=$((FAILED + 1))
        # Continue with remaining migrations
    fi
done

echo ""
echo "============================================"
echo "Migration Complete"
echo "============================================"
echo "Total:   $TOTAL"
echo "Success: $SUCCESS"
echo "Failed:  $FAILED"
echo ""

# Count tables
TABLE_COUNT=$(run_psql_cmd \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null | tr -d ' ')

echo "Tables created: $TABLE_COUNT / 248"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "WARNING: Some migrations failed. Check logs above."
    exit 1
fi

echo "All migrations completed successfully."
