# Lambda Cold Start Benchmark

Vergleichsstudie Cold-Start-Latenz auf AWS Lambda fuer vier Runtimes:

- **Java 25** auf Amazon Corretto, Quarkus-Workload (Lambda runtime `java25`)
- **Java 25 mit AWS SnapStart**, Quarkus-Workload, gemessen mit und ohne CRaC-Priming
- **Native** via GraalVM/Mandrel, Quarkus-Workload (Lambda runtime `provided.al2023`)
- **Node.js 24** (Lambda runtime `nodejs24.x`)

Identische Workload in allen Runtimes, definiert im [Workload-Contract](workload/contract.md): JSON rein, UUID validieren, SHA-256 berechnen, in DynamoDB schreiben und wieder lesen, JSON raus.

**Studienbericht:** https://go.k-i-soft.ch/w8ekxh

---

## Headline-Ergebnisse

Cold Start Total Duration p50 bei 1024 MB Memory, 1 KB Payload, eu-central-2, arm64:

| Runtime | Cold Total p50 | vs Native |
|---|---:|---:|
| Java 25 | 3320 ms | 7.8x |
| Java 25 + SnapStart | 5463 ms | 12.9x |
| **Native (GraalVM)** | **425 ms** | **1.0x** |
| Node.js 24 | 430 ms | 1.0x |

Mit CRaC-Priming wurde SnapStart auf 5698 ms gemessen, plus 4 Prozent im Rauschen, kein messbarer Vorteil. Vollstaendige Tabelle (alle Memory- und Payload-Stufen) liegt in [`results/summary.csv`](results/summary.csv), aggregierter Markdown-Report in [`results/report.md`](results/report.md), Roh-CSVs in [`results/raw/`](results/raw/).

---

## Quick Start

Reproduktion eines vollstaendigen Laufs mit allen vier Varianten:

```bash
git clone https://github.com/k-i-soft/lambda-coldstart-bench
cd lambda-coldstart-bench

# 1. AWS-Credentials setzen
export AWS_PROFILE=...
aws sts get-caller-identity

# 2. Build und Deploy (~10 Min beim ersten Run, Mandrel-Container-Pull)
cd cdk
npm install
npm run build:artifacts
npx cdk bootstrap aws://<account>/eu-central-2   # einmalig pro Account
npm run deploy

# 3. Benchmark laufen lassen (~9 Stunden gesamt fuer alle drei Runs)
cd ../bench
./run.sh                                          # ~4 h, Standard-Runtimes
SNAPSTART_VARIANT=default ./run-snapstart.sh      # ~2.5 h, SnapStart ohne Priming
SNAPSTART_VARIANT=primed  ./run-snapstart.sh      # ~2.5 h, SnapStart mit Priming

# 4. Auswertung
awk 'FNR==1 && NR!=1 {next} {print}' \
  ../results/raw/measurements-*.csv \
  > ../results/raw/combined.csv
python3 analyze.py ../results/raw/combined.csv ../results/

# 5. Aufraeumen
cd ../cdk && npm run destroy
```

Geschaetzte Kosten fuer einen kompletten Lauf in eu-central-2: deutlich unter 10 CHF (Lambda Free Tier deckt einen guten Teil, DynamoDB On-Demand entsprechend wenig).

---

## Repository-Struktur

```
lambda-coldstart-bench/
  runtimes/
    java/        Quarkus 3.34, eine Codebasis fuer JVM- und Native-Build (mvn vs mvn -Dnative)
    node/        Node.js 24 Handler, ESM
  workload/      Workload-Contract, verbindlich fuer alle Runtimes
  cdk/           CDK App, deployt 12 Functions plus DynamoDB, arm64
  bench/         Test-Runner (run.sh, run-snapstart.sh) plus Analyzer (analyze.py)
  bench/local/   Lokaler Smoke-Test gegen DynamoDB Local, ohne AWS
  results/       Roh-CSVs aus den Messlaeufen plus aggregierte Reports
```

Detaildoku in den jeweiligen Unterordnern: [`cdk/README.md`](cdk/README.md), [`bench/README.md`](bench/README.md), [`bench/local/README.md`](bench/local/README.md).

---

## Voraussetzungen

- AWS CLI v2, eingerichtet mit einem Profil das Lambda, DynamoDB, IAM, CloudWatch Logs und CloudFormation darf
- Node.js 18+ (fuer CDK), Maven plus JDK 21+ (fuer Quarkus-Build), Docker (fuer den Native-Build im Mandrel-Container)
- `jq`, `python3` 3.10+ (Walrus-Operator im Analyzer), `bash` 3.2+

---

## Build-Details

### Quarkus JVM JAR

```bash
cd runtimes/java
mvn package
```

Artefakt: `target/function.zip`. Lambda-Konfiguration: Runtime `java25` (Amazon Corretto), Handler `io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest`.

### Quarkus Native via GraalVM/Mandrel

```bash
cd runtimes/java
mvn package -Dnative
```

Build laeuft im Mandrel-Container, kein lokales GraalVM noetig (`quarkus.native.container-build=true`). Erstes Pull-Down ~1.5 GB. Artefakt: `target/function.zip` mit `bootstrap`-Binary. Lambda-Konfiguration: Runtime `provided.al2023`, Architektur muss zur Build-Plattform passen.

### Node.js 24

```bash
cd runtimes/node
zip -r ../../build/node.zip src/handler.mjs package.json
```

`@aws-sdk/client-dynamodb` ist in der Lambda Node 24 Runtime bereits enthalten und wird nicht mitgepackt. Lokal nur als devDependency fuer IDE-Support.

Das CDK-Skript `cdk/scripts/build-artifacts.sh` orchestriert alle drei Builds in einem Durchgang.

---

## Was bewusst nicht gemessen wird

- **VPC-Lambdas**: anderes Cold-Start-Profil (ENI-Setup), eigene Studie
- **Provisioned Concurrency**: kein Cold Start vorhanden, Praxis-Loesung statt Vergleichs-Setup
- **Lambda@Edge**: anderer Stack, anderer Use-Case
- **API Gateway davor**: wuerde HTTP-Layer-Latenz dazumischen, wir invoken direkt via `aws lambda invoke`

Detaillierte Methodik im [Workload-Contract](workload/contract.md) und in [`bench/README.md`](bench/README.md).

---

## Studienbericht

Vollstaendige Analyse mit Methodik, Caveats, Visualisierung und Praxis-Empfehlungen:

**Studienbericht:** https://go.k-i-soft.ch/w8ekxh

---

## License

MIT, siehe [`LICENSE`](LICENSE).

Datenfreigabe: die Roh-CSVs in `results/raw/` sind unter derselben Lizenz frei nutzbar. Wer die Studie ergaenzt oder repliziert, freut sich vermutlich ueber einen Link zurueck.

## Author

Istvan Kappelmayer, K-I-Soft, Schweiz. https://www.k-i-soft.ch
