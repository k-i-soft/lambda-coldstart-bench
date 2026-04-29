# Bench Runner

Drei Komponenten:

| Datei | Zweck |
|---|---|
| `config.json` | beschreibt 54 Konfigurationen (Runtime x Memory x Payload x Mode) |
| `build-payload.py` | erzeugt JSON-Payload mit frischer UUID, Ziel-Bytelaenge |
| `run.sh` | iteriert ueber alle Konfigurationen, forciert Cold Starts via Env-Var-Bump, schreibt CSV |
| `run-snapstart.sh` | Variante fuer SnapStart-Functions, forciert Cold via publish-version + alias-update |
| `analyze.py` | liest CSV, berechnet p50/p95/p99 pro Konfig, schreibt summary.csv und report.md |

## Voraussetzungen

- AWS CLI v2, eingerichtet mit Profil das `lambda:*` und `lambda:UpdateFunctionConfiguration` darf
- `jq`, `python3` (3.10+ wegen Walrus-Operator), `bash` (3.2 reicht)
- Deployte Lambda-Functions nach Schema `bench-{runtime}-{memory}` (Phase 3, CDK)
- DynamoDB-Tabelle `BenchTable` mit PK `id` (String)

## Trockendurchlauf

Verifiziert die Pipeline ohne AWS-Aufrufe. Erzeugt fake REPORT-Zeilen.

```bash
DRY_RUN=1 ./run.sh
python3 analyze.py
```

## Echter Lauf

```bash
./run.sh                                        # liest config.json, schreibt results/raw/measurements-<ts>.csv
python3 analyze.py                              # neueste measurements-CSV automatisch
python3 analyze.py results/raw/measurements-X.csv results/  # explizit
```

Ergebnis: `results/summary.csv` plus `results/report.md` mit Pivot-Tabellen.

## SnapStart-Lauf (separat)

```bash
./run-snapstart.sh                              # 25 Iterationen pro Konfig, ~2.5h
# CSVs zusammenfuegen (gleiches Schema, neue Zeilen mit runtime=java-jvm-snapstart)
cat ../results/raw/measurements-*.csv \
  | awk 'NR==1 || !/^timestamp,/' \
  > ../results/raw/combined.csv
python3 analyze.py ../results/raw/combined.csv ../results/
```

Cold-Start-Forcierung laeuft anders als bei `run.sh`: pro Iteration wird eine neue Version published, der Snapshot abgewartet (~10-30 s) und der Alias `live` umgelegt. Ohne diesen Workaround wuerde `update-function-configuration` nur `$LATEST` aendern, der aliasierte Snapshot bliebe unberuehrt.

Default 25 Iterationen, ueber `SNAPSTART_ITER=N` ueberschreibbar. Default Snapshot-Timeout 90 s, ueber `SNAPSHOT_TIMEOUT_SEC=N`.

## Methodik

- **Cold Start forcieren (Standard):** `aws lambda update-function-configuration` setzt eine Nonce-Env-Var. Lambda recycelt dadurch alle Container. `aws lambda wait function-updated` blockt bis die neue Konfig aktiv ist.
- **Cold Start forcieren (SnapStart):** Env-Var-Bump auf `$LATEST` plus `publish-version` plus `update-alias`. Pro Iteration ~30-45 s wegen Snapshot-Erstellung.
- **Warm Phase:** zwei Warmup-Invocations (nicht gemessen), dann 50 (oder 25 fuer SnapStart) echte Messungen ohne Konfig-Aenderung.
- **Frische UUID pro Invoke:** verhindert DDB-Caching-Effekte.
- **Mess-Datenquelle:** `aws lambda invoke --log-type Tail` liefert die REPORT-Zeile direkt im Response-Header. Kein Warten auf CloudWatch-Logs-Ingestion. Bash-Regex parst `Init Duration` (Standard) **oder** `Restore Duration` (SnapStart) in dieselbe `init_duration_ms`-Spalte. So bleibt `analyze.py` runtime-agnostisch.

## Geschaetzte Laufzeit

**run.sh** (3 runtime x 3 memory x 3 payload, 50 cold + 50 warm):
- Cold: ~10 s pro Iteration (Update-Wait plus Invoke) -> ~8 min
- Warm: ~0.5 s pro Iteration -> ~30 s
- Summe: 27 Konfigs x ~9 min = **~4 Stunden**

**run-snapstart.sh** (1 runtime x 3 memory x 3 payload, 25 cold + 25 warm):
- Cold: ~45 s pro Iteration (publish + snapshot + alias + invoke) -> ~19 min
- Warm: ~0.5 s pro Iteration -> ~15 s
- Summe: 9 Konfigs x ~19 min = **~2.5 Stunden**

**Lambda-Kosten gesamt (in eu-central-2):**
- run.sh: 2700 Invocations + ~1350 update-function-configuration (gratis)
- run-snapstart.sh: 450 Cold + 450 Warm Invocations + 225 publish-version (gratis)
- DynamoDB On-Demand: ~7000 schreib- und ~7000 lese-Operationen
- **Gesamtkosten: deutlich unter 10 CHF**

## Was fehlt noch (Phase 3)

- CDK-Konstrukt das die 9 Lambda-Functions (3 Runtimes x 3 Memory) plus DynamoDB-Tabelle deployt. Architektur arm64. IAM-Rollen mit `dynamodb:PutItem` und `dynamodb:GetItem` auf `BenchTable`.
