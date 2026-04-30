import * as path from "path";
import { Construct } from "constructs";
import {
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
  CfnOutput,
} from "aws-cdk-lib";
import {
  AttributeType,
  BillingMode,
  Table,
} from "aws-cdk-lib/aws-dynamodb";
import {
  Alias,
  Architecture,
  Code,
  Function as LambdaFunction,
  Runtime,
  SnapStartConf,
  Tracing,
  LoggingFormat,
} from "aws-cdk-lib/aws-lambda";
import { LogGroup, RetentionDays } from "aws-cdk-lib/aws-logs";
import {
  ManagedPolicy,
  Role,
  ServicePrincipal,
} from "aws-cdk-lib/aws-iam";

/**
 * Lambda Cold Start Benchmark Stack.
 *
 * Deployt eine DynamoDB-Tabelle und 9 Lambda-Functions
 * (3 Runtimes x 3 Memory-Stufen) mit absichtlich minimaler Konfiguration:
 *
 * - kein SnapStart  (verfaelscht JVM-Cold-Start)
 * - kein X-Ray      (Init-Hook, ~30 ms)
 * - keine Insights  (zusaetzlicher Layer)
 * - kein VPC        (anderes Cold-Start-Profil)
 * - keine Provisioned Concurrency
 *
 * Ziel: ehrliche Cold-Start-Messung der reinen Runtime-Initialisierung.
 */

interface RuntimeSpec {
  readonly key: "java-jvm" | "java-native" | "node";
  readonly runtime: Runtime;
  readonly handler: string;
  readonly artifactPath: string;
}

const PROJECT_ROOT = path.join(__dirname, "..", "..");

const RUNTIME_SPECS: RuntimeSpec[] = [
  {
    key: "java-jvm",
    runtime: Runtime.JAVA_25,
    handler: "io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest",
    artifactPath: path.join(PROJECT_ROOT, "runtimes", "java", "dist", "jvm", "function.zip"),
  },
  {
    key: "java-native",
    runtime: Runtime.PROVIDED_AL2023,
    handler: "not.used.in.provided.runtime",
    artifactPath: path.join(PROJECT_ROOT, "runtimes", "java", "dist", "native", "function.zip"),
  },
  {
    key: "node",
    runtime: Runtime.NODEJS_24_X,
    handler: "src/handler.handler",
    artifactPath: path.join(PROJECT_ROOT, "runtimes", "node", "dist", "node.zip"),
  },
];

const MEMORY_SIZES_MB = [512, 1024, 1769];

export class BenchStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const table = new Table(this, "BenchTable", {
      tableName: "BenchTable",
      partitionKey: { name: "id", type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const role = new Role(this, "BenchLambdaRole", {
      roleName: "lambda-coldstart-bench-role",
      assumedBy: new ServicePrincipal("lambda.amazonaws.com"),
    });
    role.addManagedPolicy(
      ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"),
    );
    table.grantReadWriteData(role);

    for (const spec of RUNTIME_SPECS) {
      for (const memory of MEMORY_SIZES_MB) {
        const fnName = `bench-${spec.key}-${memory}`;
        const logGroup = new LogGroup(this, `${fnName}-LogGroup`, {
          logGroupName: `/aws/lambda/${fnName}`,
          retention: RetentionDays.THREE_DAYS,
          removalPolicy: RemovalPolicy.DESTROY,
        });

        new LambdaFunction(this, fnName, {
          functionName: fnName,
          runtime: spec.runtime,
          handler: spec.handler,
          code: Code.fromAsset(spec.artifactPath),
          architecture: Architecture.ARM_64,
          memorySize: memory,
          timeout: Duration.seconds(30),
          role,
          environment: {
            BENCH_TABLE: table.tableName,
            BENCH_RUNTIME: spec.key,
            BENCH_RUN: "init",
          },
          logGroup,
          tracing: Tracing.DISABLED,
          loggingFormat: LoggingFormat.TEXT,
        });
      }
    }

    // SnapStart-Varianten des Quarkus JVM Handlers.
    // Gleiche Code-Basis wie bench-java-jvm, aber mit SnapStart aktiviert
    // und einem Alias "live" auf der ersten publishten Version.
    //
    // Zwei Varianten werden deployt:
    //   - "default":  ohne CRaC-Priming, Out-of-the-Box-SnapStart
    //   - "primed":   BENCH_PRIME=true, Handler registriert sich bei CRaC und
    //                 ruft sich selbst einmal vor dem Snapshot auf
    const jvmArtifact = path.join(PROJECT_ROOT, "runtimes", "java", "dist", "jvm", "function.zip");
    const snapStartVariants: Array<{ key: string; runtimeKey: string; primed: boolean }> = [
      { key: "snapstart",         runtimeKey: "java-jvm-snapstart",        primed: false },
      { key: "snapstart-primed",  runtimeKey: "java-jvm-snapstart-primed", primed: true  },
    ];

    for (const variant of snapStartVariants) {
      for (const memory of MEMORY_SIZES_MB) {
        const fnName = `bench-java-jvm-${variant.key}-${memory}`;
        const logGroup = new LogGroup(this, `${fnName}-LogGroup`, {
          logGroupName: `/aws/lambda/${fnName}`,
          retention: RetentionDays.THREE_DAYS,
          removalPolicy: RemovalPolicy.DESTROY,
        });

        const fn = new LambdaFunction(this, fnName, {
          functionName: fnName,
          runtime: Runtime.JAVA_25,
          handler: "io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest",
          code: Code.fromAsset(jvmArtifact),
          architecture: Architecture.ARM_64,
          memorySize: memory,
          timeout: Duration.seconds(30),
          role,
          environment: {
            BENCH_TABLE: table.tableName,
            BENCH_RUNTIME: variant.runtimeKey,
            BENCH_RUN: "init",
            BENCH_PRIME: variant.primed ? "true" : "false",
          },
          logGroup,
          tracing: Tracing.DISABLED,
          loggingFormat: LoggingFormat.TEXT,
          snapStart: SnapStartConf.ON_PUBLISHED_VERSIONS,
        });

        new Alias(this, `${fnName}-alias`, {
          aliasName: "live",
          version: fn.currentVersion,
        });
      }
    }

    new CfnOutput(this, "TableName", { value: table.tableName });
    new CfnOutput(this, "Region", { value: this.region });
  }
}
