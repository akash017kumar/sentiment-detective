# Sentiment Detective — Automated Review Analysis Pipeline on AWS

> **Serverless NLP pipeline** that automatically analyzes customer reviews using AWS Lambda, Amazon Bedrock (Gemma 3 AI model), DynamoDB, S3, SNS, and CloudWatch — deployed end-to-end via CloudFormation IaC.

---

## Architecture

```
Customer Review (.txt)
        │
        ▼
   Amazon S3          ← Content storage trigger
        │ (S3 Event)
        ▼
  AWS Lambda          ← Serverless compute (Python 3.12)
        │ (API call)
        ▼
Amazon Bedrock        ← AI inference (Gemma 3 4B via Bedrock Mantle)
  (Gemma 3 4B)
        │ (structured JSON response)
        ▼
   Amazon DynamoDB    ← Results storage with GSI for fast queries
        │
        ├──▶ Amazon SNS       ← Email alerts for negative/urgent reviews
        │
        └──▶ CloudWatch       ← Monitoring, dashboards & alarms
```

---

## What This Project Does

Businesses receive thousands of customer reviews daily. Manually reading and categorizing them is slow, expensive, and error-prone.

This pipeline solves that problem by:

1. **Detecting** when a new review file lands in S3
2. **Analyzing** it automatically using a generative AI model via Amazon Bedrock
3. **Extracting** sentiment, urgency level, key topics, and a one-line summary
4. **Storing** structured results in DynamoDB for instant querying
5. **Alerting** teams via email when negative or high-urgency content is detected
6. **Monitoring** the entire pipeline via CloudWatch dashboards and alarms

**Zero manual intervention required after deployment.**

---

## Tech Stack

| Service | Purpose |
|---|---|
| **Amazon S3** | Review file storage + event trigger |
| **AWS Lambda** (Python 3.12) | Serverless processing engine |
| **Amazon Bedrock** (Gemma 3 4B) | AI-powered sentiment analysis |
| **Amazon DynamoDB** | Results storage with GSI indexing |
| **Amazon SNS** | Email alerts for negative/urgent reviews |
| **Amazon CloudWatch** | Monitoring, dashboards, and error alarms |
| **AWS CloudFormation** | Full infrastructure as code (IaC) |
| **AWS IAM** | Least-privilege role and policy management |

---

## Output Schema

Each analyzed review produces a structured record in DynamoDB:

```json
{
  "id": "uuid",
  "timestamp": "2026-06-10T05:30:00Z",
  "s3_key": "reviews/review-1.txt",
  "sentiment": "negative",
  "sentiment_score": "-0.9",
  "key_topics": ["product malfunction", "refund request"],
  "urgency_level": "high",
  "summary": "Customer reports product failure and demands immediate refund.",
  "action_required": true,
  "preview": "First 300 chars of review..."
}
```

---

## Project Structure

```
sentiment-detective/
├── cfn/
│   └── template.yaml          # CloudFormation IaC — all 7 AWS resources
├── lambda/
│   └── handler.py             # Lambda function (S3 → Bedrock → DynamoDB → SNS)
├── scripts/
│   ├── deploy.sh              # One-command deploy script (runs in AWS CloudShell)
│   └── test.sh                # Upload test reviews and validate pipeline
├── sample-reviews/
│   ├── negative-urgent.txt    # Test review — negative sentiment
│   ├── positive-happy.txt     # Test review — positive sentiment
│   └── neutral-feedback.txt   # Test review — neutral sentiment
├── docs/
│   └── architecture.md        # Detailed architecture decisions
└── README.md
```

---

## Deployment (One Command via AWS CloudShell)

**No local setup required.** Runs 100% in AWS CloudShell — just a browser.

### Prerequisites

- AWS account with IAM permissions for: CloudFormation, S3, Lambda, DynamoDB, SNS, Bedrock, CloudWatch, IAM
- Amazon Bedrock — Gemma 3 4B model available (auto-enabled in supported regions)

### Steps

**1. Open AWS CloudShell**
```
AWS Console → search "CloudShell" → click the terminal icon (>_)
```

**2. Clone this repository**
```bash
git clone https://github.com/YOUR_USERNAME/sentiment-detective.git
cd sentiment-detective
chmod +x scripts/deploy.sh
```

**3. Deploy**
```bash
./scripts/deploy.sh your@email.com us-east-1
```

**4. Confirm SNS subscription**
Check your email and click the confirmation link from AWS.

**Done.** The pipeline is live.

---

## Usage

Once deployed, drop any `.txt` file into the S3 bucket:

```bash
# Via AWS CLI
aws s3 cp review.txt s3://sentiment-detective-content-<account-id>/reviews/review.txt

# Or via AWS Console
# S3 → sentiment-detective-content-<account-id> → Upload → select .txt file
```

Results appear in DynamoDB within **~10 seconds**.

---

## Query Results

```bash
# All results
aws dynamodb scan --table-name sentiment-detective-results --output table

# Only negative reviews
aws dynamodb query \
  --table-name sentiment-detective-results \
  --index-name sentiment-index \
  --key-condition-expression "sentiment = :s" \
  --expression-attribute-values '{":s":{"S":"negative"}}' \
  --output table

# Export to CSV
aws dynamodb scan \
  --table-name sentiment-detective-results \
  --output json > results.json
```

---

## Key Engineering Decisions

**Why Lambda over EC2?**
Serverless scales to zero cost when idle and auto-scales on traffic spikes — ideal for event-driven review ingestion.

**Why DynamoDB over RDS?**
Schema-less design accommodates variable AI output fields. GSI on `sentiment` field enables O(1) filtered queries without full table scans.

**Why CloudFormation?**
IaC ensures the entire stack is reproducible, version-controlled, and deployable in any AWS region with a single command — no manual console clicks.

**Why Bedrock Mantle endpoint?**
Bedrock Mantle uses the latest routing and provides access to open-weight models (Gemma, Mistral, etc.) without model access approval delays.

**Least-privilege IAM:**
Lambda role grants only the exact permissions needed — `s3:GetObject`, `dynamodb:PutItem`, `bedrock:Converse`, `sns:Publish`. No wildcard admin permissions.

---

## Cost Estimate

| Service | Monthly cost (1,000 reviews) |
|---|---|
| Lambda | ~$0.00 (free tier) |
| Bedrock (Gemma 3 4B) | ~$0.04 |
| DynamoDB | ~$0.00 (pay-per-request) |
| S3 | ~$0.01 |
| SNS | ~$0.00 (first 1,000 emails free) |
| **Total** | **~$0.05/month** |

---

## Tear Down

```bash
# Empty the S3 bucket first
aws s3 rb s3://sentiment-detective-content-<account-id> --force

# Delete the entire stack
aws cloudformation delete-stack --stack-name sentiment-detective
```

All resources deleted. Zero ongoing cost.

---

## Author

**Akash Kumar Nahak**
Cloud Operations / DevOps Engineer | AWS Certified AI Practitioner
[LinkedIn](https://linkedin.com/in/YOUR_LINKEDIN) | [GitHub](https://github.com/YOUR_USERNAME)
