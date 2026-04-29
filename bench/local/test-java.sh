#!/usr/bin/env bash
# Smoke-Test fuer den Quarkus-Handler gegen lokale DynamoDB.
# Voraussetzung: in einem zweiten Terminal laeuft "mvn quarkus:dev"
#                aus runtimes/java/, das auf Port 8080 lauscht.
#                setup.sh hat DDB Local gestartet.

set -euo pipefail

ENDPOINT="${QUARKUS_DEV_ENDPOINT:-http://localhost:8080}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! curl -fsS "$ENDPOINT" >/dev/null 2>&1 && ! curl -fsS -X POST "$ENDPOINT" -d '{}' >/dev/null 2>&1; then
  echo "Quarkus Dev-Mode laeuft nicht auf $ENDPOINT" >&2
  echo "Starte in einem zweiten Terminal:" >&2
  echo "  cd runtimes/java && mvn quarkus:dev" >&2
  exit 1
fi

pass=0
event_file=$(mktemp)
resp_file=$(mktemp)
trap 'rm -f "$event_file" "$resp_file"' EXIT

for label in 1k 100k 1m; do
  python3 "$SCRIPT_DIR/../build-payload.py" "$label" > "$event_file"
  curl -fsS -X POST -H "Content-Type: application/json" \
    --data-binary "@$event_file" "$ENDPOINT" -o "$resp_file"

  in_id=$(python3 -c "import json;print(json.load(open('$event_file'))['id'])")
  out_id=$(python3 -c "import json;print(json.load(open('$resp_file')).get('id',''))")
  hash=$(python3 -c "import json;print(json.load(open('$resp_file')).get('payloadHash',''))")
  size=$(python3 -c "import json;print(json.load(open('$resp_file')).get('payloadSize',''))")

  if [[ "$in_id" != "$out_id" ]]; then
    echo "FAIL $label: id roundtrip ($in_id != $out_id)" >&2
    echo "  response: $resp" >&2
    exit 1
  fi
  if [[ ${#hash} -ne 64 ]]; then
    echo "FAIL $label: hash length ${#hash}" >&2
    exit 1
  fi
  echo "  $label: OK  hash=${hash:0:12}...  size=$size"
  pass=$((pass + 1))
done

# Validation-Fehler
resp=$(curl -fsS -X POST -H "Content-Type: application/json" \
  -d '{"id":"not-a-uuid","payload":"x"}' "$ENDPOINT")
err=$(echo "$resp" | python3 -c "import json,sys;print(json.load(sys.stdin).get('error',''))")
if [[ -z "$err" ]]; then
  echo "FAIL validation: kein error-Feld in response" >&2
  exit 1
fi
echo "  validation: OK  error=\"$err\""
pass=$((pass + 1))

echo ""
echo "$pass Tests OK"
