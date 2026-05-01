# Lambda Cold Start Benchmark, CDK

Eigenstaendige CDK-App, deployt 12 Lambda-Functions plus eine DynamoDB-Tabelle in eu-central-2. Alles arm64.

## Architektur

| | |
|---|---|
| Tabelle | `BenchTable` (PK `id`, On-Demand, RemovalPolicy DESTROY) |
| Functions Standard | `bench-{runtime}-{memory}` fuer runtime in `[java-jvm, java-native, node]` und memory in `[512, 1024, 1769]` -> **9 Functions** |
| Functions SnapStart | `bench-java-jvm-snapstart-{memory}` und `bench-java-jvm-snapstart-primed-{memory}` mit `SnapStartConf.ON_PUBLISHED_VERSIONS` und Alias `live` -> **6 Functions**, BENCH_PRIME=false bzw. true unterscheidet die zwei Varianten |
| **Total** | **12 Lambda-Functions, 6 Aliase** |
| Architektur | arm64 (Graviton) |
| Logs | `/aws/lambda/<fn>`, Retention 3 Tage |
| Bewusst NICHT aktiviert | X-Ray, Insights, VPC, Provisioned Concurrency. Jede dieser Optionen verfaelscht die Cold-Start-Messung. |
| IAM | Eine geteilte Rolle ueber alle 12 Functions, `dynamodb:PutItem` plus `GetItem` auf `BenchTable`, plus Basic-Lambda-Execution. |

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

Nach erfolgreichem Deploy stehen 12 Functions in eu-central-2 bereit. Dann zurueck zu `bench/`:

```bash
cd ../bench
./run.sh                                          # ~4 h, Standard-Runtimes
SNAPSTART_VARIANT=default ./run-snapstart.sh      # ~2.5 h, SnapStart ohne Priming
SNAPSTART_VARIANT=primed  ./run-snapstart.sh      # ~2.5 h, SnapStart mit CRaC-Priming
python3 analyze.py                                # erzeugt results/summary.csv und results/report.md
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

- **API Gateway**: Tests rufen Lambdas direkt via `aws lambda invoke` auf. Kein API Gateway noetig, das wuerde nur HTTP-Layer-Latenz dazumischen
- **SQS / SNS Trigger**: Async-Trigger haben anderes Init-Profil, wir messen synchrones Invoke
- **VPC Endpoints**: alle Functions reden ueber das normale Internet zum DDB-Service-Endpoint, das matched die haeufigste Praxis-Konfiguration

## Warum keine eigene Production-Construct-Library

Wer in einer existierenden Codebasis schon einen Higher-Level Lambda-Construct hat (mit X-Ray, Insights, Tracing, SnapStart-Defaults und so), sollte ihn fuer diesen Bench **nicht** benutzen. Jede dieser Production-Annehmlichkeiten verfaelscht das Cold-Start-Profil. Dieser Stack nutzt absichtlich `aws-cdk-lib`'s nacktes `Function`-Konstrukt mit jedem mess-relevanten Hook explizit deaktiviert, damit die Messung sauber bleibt.
