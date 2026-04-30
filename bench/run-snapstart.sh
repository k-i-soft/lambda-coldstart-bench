#!/usr/bin/env bash
# SnapStart Bench Runner
#
# Misst Restore Duration aus dem REPORT-Feld der SnapStart-Functions.
# Pro Iteration:
#   1. Description-Bump auf $LATEST           -> erzwingt neuen RevisionId
#   2. publish-version                        -> erzeugt neuen Snapshot, ~10-30 s
#   3. Polling auf State=Active               -> wartet bis Snapshot bereit
#   4. update-alias live -> N                 -> Alias zeigt auf neue Version
#   5. invoke <fn>:live                       -> Restore aus dem neuen Snapshot
#
# Hinweis: AWS bietet keinen schnellen Mechanismus um warme Instanzen einer
# aliasierten Version zu evicten. Concurrency-0-Trick wirkt erst nach
# Minuten, update-function-configuration aendert nur $LATEST. Also
# publishen wir pro Iteration neu. Snapshots altern nicht, die Restore
# Duration ist fuer Messzwecke aequivalent zu einem reused-Snapshot.
#
# Parser akzeptiert "Restore Duration:" zusaetzlich zu "Init Duration:" und
# schreibt beides in dieselbe init_duration_ms-Spalte.
#
# Usage:
#   ./run-snapstart.sh [config.json] [out.csv]
#   DRY_RUN=1 ./run-snapstart.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/config.json}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/results/raw/measurements-snapstart-$(date -u +%Y%m%dT%H%M%SZ).csv}"
DRY_RUN="${DRY_RUN:-0}"

RUNTIME_KEY="java-jvm-snapstart"
ALIAS_NAME="live"
ITER="${SNAPSTART_ITER:-25}"
WARMUP="${SNAPSTART_WARMUP:-2}"
FN_PATTERN="bench-java-jvm-snapstart-{memory}"
SNAPSHOT_TIMEOUT_SEC="${SNAPSHOT_TIMEOUT_SEC:-90}"
CLEANUP_INTERVAL="${CLEANUP_INTERVAL:-5}"

for cmd in jq aws python3 base64; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd nicht gefunden" >&2; exit 1; }
done

REGION=$(jq -r .region "$CONFIG_FILE")
TABLE=$(jq -r .tableName "$CONFIG_FILE")

MEMORIES=()
PAYLOADS=()
while IFS= read -r line; do MEMORIES+=("$line"); done < <(jq -r '.memorySizes[]' "$CONFIG_FILE")
while IFS= read -r line; do PAYLOADS+=("$line"); done < <(jq -r '.payloadSizes[]' "$CONFIG_FILE")

fn_name() {
  local memory=$1
  local n=$FN_PATTERN
  echo "${n//\{memory\}/$memory}"
}

# Erzwingt einen frischen Restore: bumpt Description auf $LATEST, publisht eine
# neue Version (mit eigenem Snapshot), wartet bis State=Active, legt Alias um.
# Echo der neuen Versionsnummer auf stdout, Diagnostik auf stderr.
publish_and_wait() {
  local fn=$1
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY-V-$RANDOM"
    return
  fi

  aws lambda update-function-configuration \
    --region "$REGION" \
    --function-name "$fn" \
    --description "iter-$(date +%s%N)" \
    --output json >/dev/null
  aws lambda wait function-updated \
    --region "$REGION" \
    --function-name "$fn"

  local version
  version=$(aws lambda publish-version \
    --region "$REGION" \
    --function-name "$fn" \
    --query Version \
    --output text)

  local elapsed=0
  while (( elapsed < SNAPSHOT_TIMEOUT_SEC )); do
    local state opt_status
    state=$(aws lambda get-function-configuration \
      --region "$REGION" \
      --function-name "$fn" \
      --qualifier "$version" \
      --query State \
      --output text 2>/dev/null || echo "Pending")
    opt_status=$(aws lambda get-function-configuration \
      --region "$REGION" \
      --function-name "$fn" \
      --qualifier "$version" \
      --query 'SnapStart.OptimizationStatus' \
      --output text 2>/dev/null || echo "Off")
    if [[ "$state" == "Active" && "$opt_status" == "On" ]]; then
      echo "$version"
      return 0
    fi
    if [[ "$state" == "Failed" ]]; then
      echo "ERROR: Version $version Failed" >&2
      return 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "ERROR: Snapshot-Timeout fuer $fn:$version (state=$state, snap=$opt_status)" >&2
  return 1
}

update_alias() {
  local fn=$1 version=$2
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  aws lambda update-alias \
    --region "$REGION" \
    --function-name "$fn" \
    --name "$ALIAS_NAME" \
    --function-version "$version" >/dev/null
}

delete_old_versions() {
  local fn=$1 keep_version=$2
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  local versions
  versions=$(aws lambda list-versions-by-function \
    --region "$REGION" \
    --function-name "$fn" \
    --query 'Versions[?Version!=`$LATEST` && Version!=`'"$keep_version"'`].Version' \
    --output text 2>/dev/null || echo "")
  for v in $versions; do
    aws lambda delete-function \
      --region "$REGION" \
      --function-name "$fn" \
      --qualifier "$v" 2>/dev/null || true
  done
}

# Beim Abbruch alte Versionen aufraeumen, damit der Code-Storage nicht voll
# laeuft. Aliase nicht beruehren, die zeigen auf eine gueltige Version.
cleanup() {
  if [[ "$DRY_RUN" == "1" ]]; then return; fi
  for memory in "${MEMORIES[@]}"; do
    local fn current
    fn=$(fn_name "$memory")
    current=$(aws lambda get-alias --region "$REGION" --function-name "$fn" --name "$ALIAS_NAME" --query FunctionVersion --output text 2>/dev/null || echo "")
    [[ -n "$current" ]] && delete_old_versions "$fn" "$current"
  done
}
trap cleanup EXIT

invoke_once() {
  local target=$1 payload_file=$2 mode=$3
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$mode" == "cold" ]]; then
      echo "REPORT RequestId: 8476a536-1234-5678-9abc-$(printf '%012x' $RANDOM$RANDOM) Duration: 18.34 ms Billed Duration: 19 ms Memory Size: 1024 MB Max Memory Used: 90 MB Restore Duration: 187.42 ms"
    else
      echo "REPORT RequestId: 8476a536-1234-5678-9abc-$(printf '%012x' $RANDOM$RANDOM) Duration: 6.10 ms Billed Duration: 7 ms Memory Size: 1024 MB Max Memory Used: 90 MB"
    fi
    return
  fi
  local resp_file log_b64
  resp_file=$(mktemp)
  log_b64=$(aws lambda invoke \
    --region "$REGION" \
    --function-name "$target" \
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
  local report=$1 memory=$2 payload=$3 mode=$4
  local rid="" init="" dur="" billed="" max_mem=""
  [[ "$report" =~ RequestId:\ ([a-f0-9-]+) ]] && rid="${BASH_REMATCH[1]}"
  [[ "$report" =~ \ Duration:\ ([0-9.]+)\ ms ]] && dur="${BASH_REMATCH[1]}"
  [[ "$report" =~ Billed\ Duration:\ ([0-9]+)\ ms ]] && billed="${BASH_REMATCH[1]}"
  [[ "$report" =~ Max\ Memory\ Used:\ ([0-9]+)\ MB ]] && max_mem="${BASH_REMATCH[1]}"
  [[ "$report" =~ Init\ Duration:\ ([0-9.]+)\ ms ]] && init="${BASH_REMATCH[1]}"
  [[ "$report" =~ Restore\ Duration:\ ([0-9.]+)\ ms ]] && init="${BASH_REMATCH[1]}"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$RUNTIME_KEY" "$memory" "$payload" "$mode" \
    "$init" "$dur" "$billed" "$max_mem" "$rid"
}

mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "timestamp,runtime,memory,payload_size,mode,init_duration_ms,duration_ms,billed_duration_ms,max_memory_mb,request_id" > "$OUTPUT_FILE"

total_configs=$(( ${#MEMORIES[@]} * ${#PAYLOADS[@]} ))
config_idx=0

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN, kein AWS-Aufruf" >&2
fi

for memory in "${MEMORIES[@]}"; do
  for payload in "${PAYLOADS[@]}"; do
    config_idx=$((config_idx + 1))
    fn=$(fn_name "$memory")
    target="$fn:$ALIAS_NAME"
    echo "[$config_idx/$total_configs] $target payload=$payload (iter=$ITER)" >&2

    payload_file=$(mktemp)

    # ---- Cold phase ----
    for i in $(seq 1 "$ITER"); do
      version=$(publish_and_wait "$fn") || { echo "  cold $i/$ITER: publish failed" >&2; continue; }
      update_alias "$fn" "$version"

      python3 "$SCRIPT_DIR/build-payload.py" "$payload" > "$payload_file"
      report=$(invoke_once "$target" "$payload_file" "cold" || true)
      if [[ -n "$report" ]]; then
        if [[ "$report" != *"Restore Duration:"* && "$DRY_RUN" != "1" ]]; then
          echo "  cold $i/$ITER: WARN, kein Restore Duration im REPORT" >&2
        fi
        parse_and_emit "$report" "$memory" "$payload" "cold" >> "$OUTPUT_FILE"
      else
        echo "  cold $i/$ITER: keine REPORT-Zeile" >&2
      fi

      # Periodisch alte Versionen loeschen, sonst laeuft Code-Storage voll
      if (( i % CLEANUP_INTERVAL == 0 )); then
        delete_old_versions "$fn" "$version"
      fi
    done

    # ---- Warmup ----
    for i in $(seq 1 "$WARMUP"); do
      python3 "$SCRIPT_DIR/build-payload.py" "$payload" > "$payload_file"
      invoke_once "$target" "$payload_file" "warm" >/dev/null || true
    done

    # ---- Warm phase ----
    for i in $(seq 1 "$ITER"); do
      python3 "$SCRIPT_DIR/build-payload.py" "$payload" > "$payload_file"
      report=$(invoke_once "$target" "$payload_file" "warm" || true)
      if [[ -n "$report" ]]; then
        parse_and_emit "$report" "$memory" "$payload" "warm" >> "$OUTPUT_FILE"
      fi
    done

    rm -f "$payload_file"
  done
done

echo "fertig. CSV: $OUTPUT_FILE" >&2
