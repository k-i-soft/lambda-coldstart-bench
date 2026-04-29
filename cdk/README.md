# Lambda Cold Start Benchmark, CDK

Eigenstaendige CDK-App, deployt 9 Lambda-Functions (3 Runtimes x 3 Memory) plus DynamoDB-Tabelle in eu-central-2.

## Architektur

| | |
|---|---|
| Tabelle | `BenchTable` (PK `id`, On-Demand) |
| Functions (Standard) | `bench-{runtime}-{memory}` fuer runtime in `[java-jvm, java-native, node]` und memory in `[512, 1024, 1769]` -> 9 Functions |
| Functions (SnapStart) | `bench-java-jvm-snapstart-{memory}` mit `SnapStartConf.ON_PUBLISHED_VERSIONS` und Alias `live` -> 3 Functions |
| Architektur | arm64 (Graviton) |
| Logs | `/aws/lambda/<fn>`, Retention 3 Tage |
| **Bewusst NICHT aktiviert** (Standard) | X-Ray, Insights, VPC, Provisioned Concurrency. Begruendung: jede dieser Optionen verfaelscht die Cold-Start-Messung. |
| **SnapStart** | Nur fuer die 3 SnapStart-Functions. Eigene Methodik im SnapStart-Runner, `Restore Duration` ersetzt `Init Duration` in der REPORT-Zeile. |

## Voraussetzungen

- AWS-Profil mit Rechten auf Lambda, DynamoDB, IAM, CloudWatch Logs, CloudFormation
- Node.js 18+ (du hast 24)
- Docker (fuer Quarkus Native-Build, nicht fuer CDK selbst)
- CDK Bootstrap im Ziel-Account, falls noch nicht passiert:
  ```bash
  npx cdk bootstrap aws://<account>/eu-central-2
  ```

## Reihenfolge

```bash
cd cdk
npm install                     # einmalig
npm run build:artifacts         # baut JVM-jar, Native-Binary (~5 min Container-Build), Node-Zip
npm run synth                   # generiert CloudFormation, prueft TS-Types
npm run deploy                  # deployt Stack "LambdaColdstartBench"
```

Nach erfolgreichem Deploy stehen 9 Functions in eu-central-2 bereit. Dann zurueck zu `bench/`:

```bash
cd ../bench
./run.sh                        # ca. 4 Stunden, generiert results/raw/measurements-<ts>.csv
python3 analyze.py              # erzeugt results/summary.csv und results/report.md
```

## Selektive Builds

Falls du nur Java-JVM aendern willst:

```bash
TARGETS=jvm npm run build:artifacts
npm run deploy
```

Akzeptierte Targets: `jvm`, `native`, `node`. Default ist alle drei.

## Aufraeumen

```bash
npm run destroy
```

Loescht den ganzen Stack inklusive Tabelle und Logs (RemovalPolicy DESTROY). Passt fuer Bench-Zwecke, wuerdest du **nicht** in Prod machen.

## Region und Account

Default Region ist `eu-central-2`, ueberschreibbar via `CDK_DEFAULT_REGION`. Account wird aus deinem AWS-Profil gezogen (`CDK_DEFAULT_ACCOUNT`).

## Was nicht im Stack ist

- **API Gateway:** Tests rufen Lambdas direkt via `aws lambda invoke` auf. Kein API Gateway noetig, das wuerde ohnehin nur HTTP-Layer-Latenz dazumischen.
- **SQS / SNS Trigger:** Async-Trigger haben anderes Init-Profil, wir messen synchrones Invoke.
