#!/usr/bin/env node
import { App } from "aws-cdk-lib";
import { BenchStack } from "../lib/bench-stack";

const app = new App();

new BenchStack(app, "LambdaColdstartBench", {
  description: "Lambda Cold Start Benchmark, 9 Functions x DynamoDB",
  env: {
    region: process.env.CDK_DEFAULT_REGION ?? "eu-central-2",
    account: process.env.CDK_DEFAULT_ACCOUNT,
  },
});

app.synth();
