# Architecture Decisions — Sentiment Detective

## Overview

This document explains the key technical decisions made during the design and implementation of the Sentiment Detective pipeline.

---

## 1. Amazon Bedrock Mantle vs Standard Bedrock Runtime

**Decision:** Used Amazon Bedrock Mantle endpoint (`bedrock-mantle.<region>.api.aws/v1`)

**Why:**
- Bedrock Mantle is AWS's newer, OpenAI-compatible routing layer for foundation models
- Provides access to open-weight models (Gemma, Mistral, Qwen, etc.) without manual model access approval
- Uses the Converse API — a unified interface that works across all model providers
- Mantle-routed models use model IDs like `google.gemma-3-4b-it` (no version suffix) — simpler and forward-compatible

**Model selected:** `google.gemma-3-4b-it` (Gemma 3 4B Instruct)
- Cost: ~$0.04 per 1M input tokens
- Fast inference (~2-5 seconds per review)
- Strong instruction-following for structured JSON output

---

## 2. S3 Event Notification → Lambda

**Decision:** S3 ObjectCreated event triggers Lambda directly

**Why:**
- Zero polling cost — Lambda only runs when a file arrives
- Sub-second trigger latency
- Filtered on `.txt` suffix to avoid triggering on other file types (exports, logs)
- Decoupled — S3 and Lambda scale independently

**Alternative considered:** SQS queue between S3 and Lambda
- Rejected for this use case — adds latency and complexity without benefit at low volume
- Would reconsider at >1,000 reviews/minute to handle Lambda concurrency limits

---

## 3. DynamoDB over RDS

**Decision:** DynamoDB (NoSQL, pay-per-request) for result storage

**Why:**
- Schema-less: AI responses can vary slightly — no ALTER TABLE needed as output fields evolve
- Pay-per-request billing: zero cost when idle
- Global Secondary Index on `sentiment` field enables fast filtered queries (all negatives, all criticals)
- Single-digit millisecond read latency for downstream dashboards

**GSI Design:**
```
Primary Key: id (HASH) + timestamp (RANGE)
GSI: sentiment (HASH) + timestamp (RANGE) → named: sentiment-index
```
This allows: "give me all negative reviews sorted by time" in O(1) without scanning.

---

## 4. CloudFormation IaC

**Decision:** All resources defined in a single CloudFormation template

**Why:**
- Reproducible: entire stack deploys in one command, any region, any account
- Version-controlled: infrastructure changes tracked in Git like application code
- Rollback-safe: CloudFormation rolls back automatically on failure
- `DependsOn: LambdaInvokePermission` on S3 bucket — prevents race condition where S3 tries to configure Lambda notification before Lambda permission exists

---

## 5. IAM Least Privilege

**Decision:** Custom IAM role with minimum required permissions only

**Permissions granted:**
| Permission | Scope |
|---|---|
| `s3:GetObject` | Only the content bucket |
| `dynamodb:PutItem, Query, Scan` | Only the results table + its GSI |
| `bedrock:InvokeModel, bedrock:Converse` | All resources (Bedrock requires `*`) |
| `sns:Publish` | Only the alerts topic |
| CloudWatch Logs | Auto-granted via `AWSLambdaBasicExecutionRole` |

No `AdministratorAccess`. No wildcard service access.

---

## 6. Prompt Engineering for Structured Output

**Decision:** Prompt forces strict JSON-only output with no preamble

```
"Reply ONLY with valid JSON, nothing else."
```

**Why:**
- LLMs sometimes wrap JSON in markdown fences (```json ... ```)
- Added defensive stripping: if response starts with ```, strip the fence before parsing
- `temperature: 0.1` — low randomness for consistent, deterministic JSON structure
- `maxTokens: 512` — sufficient for the output schema, prevents runaway generation

---

## 7. SNS Alert Threshold

**Decision:** Alert fires on `sentiment == "negative"` OR `urgency in ("high", "critical")`

**Why:**
- Catches both clearly negative reviews AND urgent issues that may not be phrased negatively (e.g. a safety concern written calmly)
- Avoids alert fatigue from medium/low urgency neutral reviews
- Email delivery via SNS is free for first 1,000/month — no cost concern at this scale
