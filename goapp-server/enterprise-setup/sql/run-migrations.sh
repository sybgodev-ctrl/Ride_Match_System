#!/bin/bash
# ============================================================
# GoApp Enterprise Schema Migration Runner
# Executes all 20 migration files in order (248 tables total)
# ============================================================

set -e

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-goapp_enterprise}"
DB_USER="${DB_USER:-goapp}"
DB_PASS="${DB_PASS:-goapp}"

export PGPASSWORD="$DB_PASS"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "GoApp Enterprise Schema Migration"
echo "============================================"
echo "Host: $DB_HOST:$DB_PORT"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""

# Migration files in order
MIGRATIONS=(
    "001_identity_and_otp.sql"
    "002_driver_service.sql"
    "003_rider_service.sql"
    "004_ride_service.sql"
    "005_dispatch_matching.sql"
    "006_location_service.sql"
    "007_pricing_service.sql"
    "008_payment_wallet.sql"
    "009_driver_incentives.sql"
    "010_notification_service.sql"
    "011_fraud_risk.sql"
    "012_promotions_referrals.sql"
    "013_safety_sos.sql"
    "014_scheduling.sql"
    "015_corporate_b2b.sql"
    "016_support.sql"
    "017_compliance.sql"
    "018_saga_orchestration.sql"
    "019_event_system.sql"
    "020_analytics_warehouse.sql"
)

TOTAL=${#MIGRATIONS[@]}
SUCCESS=0
FAILED=0

for i in "${!MIGRATIONS[@]}"; do
    FILE="${MIGRATIONS[$i]}"
    NUM=$((i + 1))
    echo "[$NUM/$TOTAL] Running: $FILE"

    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SCRIPT_DIR/$FILE" > /dev/null 2>&1; then
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
TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null | tr -d ' ')

echo "Tables created: $TABLE_COUNT / 248"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "WARNING: Some migrations failed. Check logs above."
    exit 1
fi

echo "All migrations completed successfully."
