# Lokaler Smoke-Test

Verifiziert dass Java- und Node-Handler die Workload-Spec einhalten und mit DynamoDB sprechen koennen, ohne irgendwas auf AWS zu deployen.

Es geht **nur** um Korrektheit. Keine Performance-Aussage, keine Cold-Start-Messung. Native-Image lokal wird auch nicht getestet, weil das Cold-Start-Profil auf macOS sowieso nicht uebertragbar ist.

## Voraussetzungen

- Docker laeuft
- AWS CLI v2
- Maven, Java 21+ (du hast 25)
- Node 18+ (du hast 24)

## Schritte

### 1. DynamoDB Local starten

```bash
cd bench/local
./setup.sh
```

Container `bench-ddb-local` laeuft danach auf Port 8000, `BenchTable` ist erstellt.

### 2. Node-Handler testen

```bash
cd runtimes/node
npm install
cd ../../bench/local
node test-node.mjs
```

Erwartete Ausgabe: drei Payload-Stufen plus Validation-Test, alle OK.

### 3. Java-Handler testen

In einem zweiten Terminal:

```bash
cd runtimes/java
mvn quarkus:dev
```

Quarkus startet im Dev-Mode auf Port 8080 und liest das `%dev`-Profil aus `application.properties` (Endpoint Override auf DDB Local).

Im ersten Terminal:

```bash
cd bench/local
./test-java.sh
```

Erwartete Ausgabe: drei Payload-Stufen plus Validation-Test, alle OK.

### 4. Aufraeumen

```bash
cd bench/local
./teardown.sh
```

Mit `Ctrl-C` Quarkus Dev-Mode beenden.

## Was der Test prueft

- Input wird geparsed und validiert (UUID-Pruefung, leere Payload abgewiesen)
- SHA-256 wird ueber den Payload berechnet (`payloadHash`, 64 Hex-Chars)
- `payloadSize` entspricht der UTF-8 Bytelaenge
- DDB-Roundtrip funktioniert: PutItem dann GetItem mit gleicher `id`
- Response-Shape entspricht dem Contract

Beide Runtimes sollten fuer denselben Payload denselben Hash zurueckgeben. Das ist der einfachste Konsistenz-Check zwischen Java und Node.
