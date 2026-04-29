#!/usr/bin/env bash
# Lambda Cold Start Benchmark Runner
#
# Iteriert ueber alle Konfigurationen aus config.json und ruft jede deployte
# Lambda-Function 50 mal kalt (forciert via update-function-configuration) und
# 50 mal warm auf. Parst die REPORT-Zeile aus invoke --log-type Tail und
# schreibt jede Messung als Zeile in die Ergebnis-CSV.
#
# Usage:
#   ./run.sh [config.json] [out.csv]
#   DRY_RUN=1 ./run.sh        # ohne AWS-Aufrufe, fake REPORT-Zeilen
#
# Voraussetzungen: aws CLI v2, jq, python3, bash 4+.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/config.json}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/results/raw/measurements-$(date -u +%Y%m%dT%H%M%SZ).csv}"
DRY_RUN="${DRY_RUN:-0}"

# === Tools check ===
for cmd in jq aws python3 base64; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd nicht gefunden" >&2; exit 1; }
done

# === Read config ===
REGION=$(jq -r .region "$CONFIG_FILE")
TABLE=$(jq -r .tableName "$CONFIG_FILE")
ITER=$(jq -r .iterationsPerConfig "$CONFIG_FILE")
WARMUP=$(jq -r .warmupInvocations "$CONFIG_FILE")
PATTERN=$(jq -r .functionNamePattern "$CONFIG_FILE")

RUNTIMES=()
MEMORIES=()
PAYLOADS=()
while IFS= read -r line; do RUNTIMES+=("$line"); done < <(jq -r '.runtimes[]' "$CONFIG_FILE")
while IFS= read -r line; do MEMORIES+=("$line"); done < <(jq -r '.memorySizes[]' "$CONFIG_FILE")
while IFS= read -r line; do PAYLOADS+=("$line"); done < <(jq -r '.payloadSizes[]' "$CONFIG_FILE")

# === Helpers ===
fn_name() {
  local runtime=$1 memory=$2
  local n=$PATTERN
  n=${n//\{runtime\}/$runtime}
  n=${n//\{memory\}/$memory}
  echo "$n"
}

force_cold_start() {
  local fn=$1 runtime=$2
  local nonce="$RANDOM$(date +%s%N)"
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  aws lambda update-function-configuration \
    --region "$REGION" \
    --function-name "$fn" \
    --environment "Variables={BENCH_TABLE=$TABLE,BENCH_RUNTIME=$runtime,BENCH_RUN=$nonce}" \
    --output json >/dev/null
  aws lambda wait function-updated \
    --region "$REGION" \
    --function-name "$fn"
}

invoke_once() {
  local fn=$1 payload_file=$2 mode=$3
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$mode" == "cold" ]]; then
      echo "REPORT RequestId: 8476a536-1234-5678-9abc-$(printf '%012x' $RANDOM$RANDOM) Duration: 12.34 ms Billed Duration: 13 ms Memory Size: 1024 MB Max Memory Used: 50 MB Init Duration: 234.56 ms"
    else
      echo "REPORT RequestId: 8476a536-1234-5678-9abc-$(printf '%012x' $RANDOM$RANDOM) Duration: 5.67 ms Billed Duration: 6 ms Memory Size: 1024 MB Max Memory Used: 50 MB"
    fi
    return
  fi
  local resp_file log_b64
  resp_file=$(mktemp)
  log_b64=$(aws lambda invoke \
    --region "$REGION" \
    --function-name "$fn" \
    --cli-binary-format raw-in-base64-out \
    --payload "fileb://$payload_file" \
    --log-type Tail \
    --query LogResult \
    --output text \
    "$resp_file" 2>/dev/null) || { rm -f "$resp_file"; return 1; }
  rm -f "$resp_file"
  echo "$log_b64" | base64 --decode | grep "^REPORT" || true
}

parse_and_emit() {
  local report=$1 runtime=$2 memory=$3 payload=$4 mode=$5
  local rid="" init="" dur="" billed="" max_mem=""
  [[ "$report" =~ RequestId:\ ([a-f0-9-]+) ]] && rid="${BASH_REMATCH[1]}"
  [[ "$report" =~ \ Duration:\ ([0-9.]+)\ ms ]] && dur="${BASH_REMATCH[1]}"
  [[ "$report" =~ Billed\ Duration:\ ([0-9]+)\ ms ]] && billed="${BASH_REMATCH[1]}"
  [[ "$report" =~ Max\ Memory\ Used:\ ([0-9]+)\ MB ]] && max_mem="${BASH_REMATCH[1]}"
  [[ "$report" =~ Init\ Duration:\ ([0-9.]+)\ ms ]] && init="${BASH_REMATCH[1]}"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$runtime" "$memory" "$payload" "$mode" \
    "$init" "$dur" "$billed" "$max_mem" "$rid"
}

# === Main ===
mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "timestamp,runtime,memory,payload_size,mode,init_duration_ms,duration_ms,billed_duration_ms,max_memory_mb,request_id" > "$OUTPUT_FILE"

total_configs=$(( ${#RUNTIMES[@]} * ${#MEMORIES[@]} * ${#PAYLOADS[@]} ))
config_idx=0

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN, kein AWS-Aufruf" >&2
fi

for runtime in "${RUNTIMES[@]}"; do
  for memory in "${MEMORIES[@]}"; do
    for payload in "${PAYLOADS[@]}"; do
      config_idx=$((config_idx + 1))
      fn=$(fn_name "$runtime" "$memory")
      echo "[$config_idx/$total_configs] $fn payload=$payload" >&2

      payload_file=$(mktemp)

      # ---- Cold phase ----
      for i in $(seq 1 "$ITER"); do
        force_cold_start "$fn" "$runtime"
        python3 "$SCRIPT_DIR/build-payload.py" "$payload" > "$payload_file"
        report=$(invoke_once "$fn" "$payload_file" "cold" || true)
        if [[ -n "$report" ]]; then
          parse_and_emit "$report" "$runtime" "$memory" "$payload" "cold" >> "$OUTPUT_FILE"
        else
          echo "  cold $i/$ITER: keine REPORT-Zeile" >&2
        fi
      done

      # ---- Warmup (nicht gemessen) ----
      for i in $(seq 1 "$WARMUP"); do
        python3 "$SCRIPT_DIR/build-payload.py" "$payload" > "$payload_file"
        invoke_once "$fn" "$payload_file" "warm" >/dev/null || true
      done

      # ---- Warm phase ----
      for i in $(seq 1 "$ITER"); do
        python3 "$SCRIPT_DIR/build-payload.py" "$payload" > "$payload_file"
        report=$(invoke_once "$fn" "$payload_file" "warm" || true)
        if [[ -n "$report" ]]; then
          parse_and_emit "$report" "$runtime" "$memory" "$payload" "warm" >> "$OUTPUT_FILE"
        fi
      done

      rm -f "$payload_file"
    done
  done
done

echo "fertig. CSV: $OUTPUT_FILE" >&2
