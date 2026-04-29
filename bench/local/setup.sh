#!/usr/bin/env bash
# Startet DynamoDB Local und erstellt BenchTable.
# Idempotent: Container und Tabelle werden nur erstellt wenn nicht vorhanden.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENDPOINT="http://localhost:8000"
TABLE="BenchTable"

# Dummy-Credentials, DDB Local pruefst sie nicht
export AWS_ACCESS_KEY_ID="local"
export AWS_SECRET_ACCESS_KEY="local"
export AWS_REGION="us-east-1"

echo "[1/3] DynamoDB Local starten" >&2
docker compose -f "$SCRIPT_DIR/compose.yml" up -d

echo "[2/3] Auf DDB warten" >&2
for i in {1..30}; do
  if curl -fsS "$ENDPOINT" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

echo "[3/3] BenchTable anlegen" >&2
if aws dynamodb describe-table --table-name "$TABLE" --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
  echo "  Tabelle existiert bereits" >&2
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url "$ENDPOINT" >/dev/null
  echo "  Tabelle erstellt" >&2
fi

echo "" >&2
echo "DDB Local laeuft auf $ENDPOINT, Tabelle $TABLE bereit" >&2
echo "Stoppen mit: ./teardown.sh" >&2
