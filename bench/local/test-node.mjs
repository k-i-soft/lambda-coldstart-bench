// Smoke-Test fuer den Node-Handler gegen lokale DynamoDB.
// Importiert handler.mjs, ruft mit drei Payload-Groessen auf, prueft Contract.
//
// Voraussetzung: setup.sh hat DDB Local gestartet und BenchTable erstellt.
//                node_modules installiert (cd ../../runtimes/node && npm install)

process.env.AWS_ENDPOINT_URL_DYNAMODB = "http://localhost:8000";
process.env.AWS_ACCESS_KEY_ID = "local";
process.env.AWS_SECRET_ACCESS_KEY = "local";
process.env.AWS_REGION = "us-east-1";
process.env.BENCH_TABLE = "BenchTable";
process.env.BENCH_RUNTIME = "node-local";

import { randomUUID } from "node:crypto";
const { handler } = await import("../../runtimes/node/src/handler.mjs");

const SIZES = { "1k": 1024, "100k": 102400, "1m": 1048576 };

function buildPayload(label) {
  const id = randomUUID();
  const target = SIZES[label];
  const skeleton = JSON.stringify({ id, payload: "" });
  const fill = Math.max(1, target - Buffer.byteLength(skeleton, "utf8"));
  return { id, payload: "a".repeat(fill) };
}

function assert(cond, msg) {
  if (!cond) {
    console.error(`FAIL: ${msg}`);
    process.exit(1);
  }
}

let pass = 0;
for (const label of Object.keys(SIZES)) {
  const event = buildPayload(label);
  const res = await handler(event);
  assert(res.id === event.id, `${label}: id roundtrip`);
  assert(typeof res.processedAt === "string", `${label}: processedAt set`);
  assert(typeof res.payloadHash === "string" && res.payloadHash.length === 64, `${label}: hash length`);
  assert(res.runtime === "node-local", `${label}: runtime tag`);
  assert(res.payloadSize === Buffer.byteLength(event.payload, "utf8"), `${label}: size`);
  console.log(`  ${label}: OK  hash=${res.payloadHash.slice(0, 12)}...  size=${res.payloadSize}`);
  pass++;
}

// Validation-Fehler
const bad = await handler({ id: "not-a-uuid", payload: "x" });
assert(bad.error, "validation error returned");
console.log(`  validation: OK  error="${bad.error}"`);
pass++;

console.log(`\n${pass} Tests OK`);
