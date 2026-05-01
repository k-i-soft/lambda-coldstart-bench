# Bench Runner

Drei Komponenten:

| Datei | Zweck |
|---|---|
| `config.json` | beschreibt 54 Konfigurationen (Runtime x Memory x Payload x Mode) |
| `build-payload.py` | erzeugt JSON-Payload mit frischer UUID, Ziel-Bytelaenge |
| `run.sh` | iteriert ueber alle Konfigurationen, forciert Cold Starts via Env-Var-Bump, schreibt CSV |
| `run-snapstart.sh` | Variante fuer SnapStart-Functions, publishet pro Iteration eine neue Version und legt den Alias um |
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

Zwei Varianten, je per `SNAPSTART_VARIANT` waehlbar:

```bash
SNAPSTART_VARIANT=default ./run-snapstart.sh    # ohne CRaC-Priming, runtime-Key java-jvm-snapstart
SNAPSTART_VARIANT=primed  ./run-snapstart.sh    # mit CRaC-Priming,  runtime-Key java-jvm-snapstart-primed
```

Default ist `default`. Pro Variante 25 Iter x 9 Konfigs, ~2.5 h. Output-CSVs landen unter `results/raw/measurements-snapstart-{variant}-<ts>.csv`.

CSVs zusammenfuegen und analysieren:

```bash
awk 'FNR==1 && NR!=1 {next} {print}' \
  ../results/raw/measurements-*.csv \
  > ../results/raw/combined.csv
python3 analyze.py ../results/raw/combined.csv ../results/
```

Pro Iteration wird eine neue Lambda-Version published (mit eigenem Snapshot), auf Snapshot-Bereitschaft gewartet (`State=Active` plus `SnapStart.OptimizationStatus=On`) und der Alias `live` umgelegt. Der erste Invoke gegen den Alias triggert dann zwangslaeufig einen Restore aus dem neuen Snapshot.

Warum nicht das eleganter klingende "ein Snapshot, viele Restores via Concurrency-Eviction": AWS bietet keinen schnellen Mechanismus um warme Instanzen einer aliasierten Version zu evicten. `put-function-concurrency=0` wirkt erst nach Minuten, `update-function-configuration` aendert nur `$LATEST`. Methodisch ist das egal: Restore Duration aus einem frisch erstellten Snapshot ist Lambda-intern identisch zu Restore aus einem laenger lebenden Snapshot, Snapshots altern nicht.

Default 25 Iterationen, ueber `SNAPSTART_ITER=N` ueberschreibbar. Snapshot-Timeout 90 s (`SNAPSHOT_TIMEOUT_SEC`). Alle 5 Iterationen werden alte Versionen geloescht (`CLEANUP_INTERVAL`), bei Abbruch raeumt der EXIT-Trap die Function-Liste auf.

## Methodik

- **Cold Start forcieren (Standard):** `aws lambda update-function-configuration` setzt eine Nonce-Env-Var. Lambda recycelt dadurch alle Container. `aws lambda wait function-updated` blockt bis die neue Konfig aktiv ist.
- **Restore forcieren (SnapStart):** Description-Bump auf `$LATEST`, `publish-version` (erzeugt neuen Snapshot), Polling auf `State=Active` und `OptimizationStatus=On`, dann `update-alias`. Naechster Invoke ist ein garantierter Restore. Pro Iteration ~30-45 s.
- **Warm Phase:** zwei Warmup-Invocations (nicht gemessen), dann 50 (oder 25 fuer SnapStart) echte Messungen ohne Konfig-Aenderung.
- **Frische UUID pro Invoke:** verhindert DDB-Caching-Effekte.
- **Mess-Datenquelle:** `aws lambda invoke --log-type Tail` liefert die REPORT-Zeile direkt im Response-Header. Kein Warten auf CloudWatch-Logs-Ingestion. Bash-Regex parst `Init Duration` (Standard) **oder** `Restore Duration` (SnapStart) in dieselbe `init_duration_ms`-Spalte. So bleibt `analyze.py` runtime-agnostisch.

## Geschaetzte Laufzeit

**run.sh** (3 runtime x 3 memory x 3 payload, 50 cold + 50 warm):
- Cold: ~10 s pro Iteration (Update-Wait plus Invoke) -> ~8 min
- Warm: ~0.5 s pro Iteration -> ~30 s
- Summe: 27 Konfigs x ~9 min = **~4 Stunden**

**run-snapstart.sh** (1 runtime x 3 memory x 3 payload, 25 cold + 25 warm):
- Cold: ~30-45 s pro Iteration (publish + snapshot-wait + alias + invoke) -> ~15-19 min
- Warm: ~0.5 s pro Iteration -> ~15 s
- Summe: 9 Konfigs x ~17 min = **~2.5 Stunden**

**Lambda-Kosten gesamt (in eu-central-2):**
- run.sh: 2700 Invocations + ~1350 update-function-configuration (gratis)
- run-snapstart.sh: 450 Cold + 450 Warm Invocations + 225 publish-version (gratis)
- DynamoDB On-Demand: ~7000 schreib- und ~7000 lese-Operationen
- **Gesamtkosten: deutlich unter 10 CHF**

## Output-Dateien

- `results/raw/measurements-<ts>.csv`, eine Zeile pro Invoke, alle REPORT-Felder
- `results/raw/measurements-snapstart-{default|primed}-<ts>.csv`, fuer SnapStart-Runs separat
- Nach `analyze.py`: `results/summary.csv` (gruppierte p50/p95/p99) und `results/report.md` (Pivot-Tabellen)

CSV-Schema:
```
timestamp,runtime,memory,payload_size,mode,init_duration_ms,duration_ms,billed_duration_ms,max_memory_mb,request_id
```

`init_duration_ms` ist die `Init Duration` aus dem REPORT-Tail bei Standard-Runtimes oder die `Restore Duration` bei SnapStart. Damit bleibt das Schema runtime-agnostisch.
