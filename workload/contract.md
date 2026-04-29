# Workload Contract

Alle drei Runtimes (Quarkus JVM, Quarkus Native, Node.js 22) implementieren exakt dieselbe Logik. Abweichungen verfaelschen den Benchmark.

## Eingabe (Lambda Event)

```json
{
  "id": "string, UUID v4",
  "payload": "string, beliebig grosser Text (1 KB / 100 KB / 1 MB)"
}
```

## Verarbeitungsschritte

Jede Runtime fuehrt in dieser Reihenfolge aus:

1. **Parse**: Eingabe als JSON deserialisieren
2. **Validate**: `id` muss UUID-Format haben, `payload` darf nicht leer sein. Bei Fehler `400` zurueckgeben
3. **Modify**: Felder berechnen
   - `processedAt`: aktueller Zeitstempel ISO-8601
   - `payloadSize`: Bytelaenge von `payload` (UTF-8)
   - `payloadHash`: SHA-256 Hex-Digest von `payload`
   - `runtime`: einer von `java-jvm`, `java-native`, `node`
4. **Write**: PutItem in DynamoDB-Tabelle `BenchTable`
5. **Read**: GetItem mit demselben `id` zurueck aus `BenchTable`
6. **Respond**: gelesenes Item als JSON zurueckgeben

## DynamoDB Item-Struktur

```json
{
  "id":            "string (PK)",
  "processedAt":   "string ISO-8601",
  "payloadSize":   "number",
  "payloadHash":   "string, 64 hex chars",
  "runtime":       "string"
}
```

**Wichtig:** Das Original-`payload` wird nicht in DynamoDB geschrieben. Grund: 400 KB Item-Limit kollidiert mit dem 1 MB Test-Case. Die Runtime macht trotzdem die volle Arbeit (Parse, UTF-8-Bytelaenge, SHA-256 ueber den ganzen Payload), nur DynamoDB-I/O bleibt fuer alle Payload-Groessen konstant. Damit isolieren wir Runtime-Overhead von DynamoDB-Latenz-Varianz.

## Antwort (Lambda Response)

Bei Erfolg, HTTP 200 aequivalent:
```json
{
  "id": "...",
  "processedAt": "...",
  "payloadSize": 1024,
  "payloadHash": "...",
  "runtime": "java-jvm"
}
```

Bei Validierungsfehler, HTTP 400 aequivalent:
```json
{
  "error": "string"
}
```

## DynamoDB-Tabelle

- Name: `BenchTable` (ueber Env-Var `BENCH_TABLE` konfigurierbar)
- Partition Key: `id` (String)
- Kein Sort Key
- On-Demand Billing
- Region: `eu-central-2` (per Env-Var `AWS_REGION` aus Lambda-Runtime)

## Was bewusst NICHT gemacht wird

- Keine Caching-Optimierungen, die nur eine Runtime kennt
- Kein DynamoDB-Connection-Pooling-Tuning, das untypisch waere
- Kein Logging im Hot-Path (verfaelscht Messung)
- Keine externen HTTP-Calls
- Kein VPC-Lambda (anderes Cold-Start-Profil)
- Keine Provisioned Concurrency, kein SnapStart fuer Java
