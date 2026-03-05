#!/usr/bin/env bash
set -euo pipefail

TOPICS=(
  ride_requested
  ride_matching_started
  ride_broadcast_sent
  ride_accepted
  ride_completed
  surge_updated
  fraud_alert_triggered
  otp_requested
  otp_verified
)

for topic in "${TOPICS[@]}"; do
  docker exec goapp-kafka kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor 1 >/dev/null
  echo "Created/verified topic: $topic"
done
