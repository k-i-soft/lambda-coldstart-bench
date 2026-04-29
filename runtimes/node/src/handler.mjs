import { DynamoDBClient, PutItemCommand, GetItemCommand } from "@aws-sdk/client-dynamodb";
import { createHash } from "node:crypto";

const TABLE = process.env.BENCH_TABLE ?? "BenchTable";
const RUNTIME = process.env.BENCH_RUNTIME ?? "node";
const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

const ddb = new DynamoDBClient({});

export const handler = async (event) => {
  const id = event?.id;
  const payload = event?.payload;

  if (typeof id !== "string" || !UUID_RE.test(id)) {
    return { error: "id must be a valid UUID" };
  }
  if (typeof payload !== "string" || payload.length === 0) {
    return { error: "payload must be a non-empty string" };
  }

  const payloadBuf = Buffer.from(payload, "utf8");
  const payloadSize = payloadBuf.length;
  const payloadHash = createHash("sha256").update(payloadBuf).digest("hex");
  const processedAt = new Date().toISOString();

  await ddb.send(new PutItemCommand({
    TableName: TABLE,
    Item: {
      id: { S: id },
      processedAt: { S: processedAt },
      payloadSize: { N: String(payloadSize) },
      payloadHash: { S: payloadHash },
      runtime: { S: RUNTIME },
    },
  }));

  const got = await ddb.send(new GetItemCommand({
    TableName: TABLE,
    Key: { id: { S: id } },
    ConsistentRead: true,
  }));

  const a = got.Item;
  return {
    id: a.id.S,
    processedAt: a.processedAt.S,
    payloadSize: Number(a.payloadSize.N),
    payloadHash: a.payloadHash.S,
    runtime: a.runtime.S,
  };
};
