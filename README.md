# Lambda Cold Start Benchmark

Vergleichsstudie Cold-Start-Latenz auf AWS Lambda fuer drei Runtimes:
- Quarkus 3.x auf JVM (Lambda runtime `java21`)
- Quarkus 3.x Native via GraalVM (Lambda runtime `provided.al2023`)
- Node.js 22 (Lambda runtime `nodejs22.x`)

Identische Workload-Logik in allen Runtimes, definiert in [`workload/contract.md`](workload/contract.md).

## Status

- [x] Phase 1: Backend-Code (Quarkus, Node.js)
- [x] Phase 2: Test-Aufrufe und Messungen (`bench/`), per Dry-Run validiert
- [x] Phase 3: CDK-Stack (`cdk/`), `synth` ausstehend
- [ ] Build-Artefakte erzeugen, `cdk deploy`, dann echte Messung

## Repository-Struktur

```
lambda-coldstart-bench/
  runtimes/
    java/      Quarkus-Projekt, baut JVM-JAR und Native-Binary aus derselben Codebase
    node/      Node.js 22 Lambda Handler
  workload/    gemeinsamer Workload-Contract
  bench/       (Phase 2) Test-Runner und Auswertung
  results/     (Phase 2) Roh-Messungen und Reports
```

## Build

### Quarkus JVM-JAR

```bash
cd runtimes/java
./mvnw package
# Artefakt: target/function.zip (Lambda-Deployment-Paket)
# oder:    target/quarkus-app/  (Fast-Jar Layout)
```

Lambda-Konfiguration:
- Runtime: `java21`
- Handler: `io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest`
- Memory: 512 / 1024 / 1769 MB

### Quarkus Native

```bash
cd runtimes/java
./mvnw package -Dnative
# Build laeuft im Container (quarkus.native.container-build=true), keine lokale GraalVM noetig
# Artefakt: target/function.zip mit "bootstrap"-Binary
```

Lambda-Konfiguration:
- Runtime: `provided.al2023`
- Handler: `not.used.in.provided.runtime`
- Memory: 512 / 1024 / 1769 MB
- Architektur: muss zur Build-Plattform passen (`x86_64` oder `arm64`)

Hinweis: Native-Build im Container braucht laufenden Docker- oder Podman-Daemon.

### Node.js 22

```bash
cd runtimes/node
zip -r ../../build/node.zip src/handler.mjs package.json
```

`@aws-sdk/client-dynamodb` ist in der Lambda Node 22 Runtime bereits enthalten und wird **nicht** mit ins Zip gepackt. Lokal nur als devDependency fuer IDE-Support.

Lambda-Konfiguration:
- Runtime: `nodejs22.x`
- Handler: `src/handler.handler`
- Memory: 512 / 1024 / 1769 MB

## Workload

Siehe [`workload/contract.md`](workload/contract.md). Kurz: JSON rein, validieren, SHA-256 berechnen, in DynamoDB schreiben und wieder lesen, JSON raus.

## Was bewusst nicht gemessen wird

VPC-Lambdas, Provisioned Concurrency, SnapStart, Lambda@Edge. Begruendung in `workload/contract.md`.
