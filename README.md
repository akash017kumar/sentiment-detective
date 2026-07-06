# 🔍 Sentiment Detective — Automated Review Analysis Pipeline on AWS

> A serverless AI pipeline that automatically analyzes customer reviews for **sentiment, urgency, and key topics** using AWS Lambda, Amazon Bedrock (Gemma 3 AI model), DynamoDB, S3, SNS, and CloudWatch — deployed entirely via CloudFormation Infrastructure as Code.

**Built by:** [Akash Kumar Nahak](https://github.com/akash017kumar) — AWS Certified AI Practitioner

---

## 📌 What This Project Does

Every business drowns in customer reviews. Reading them manually is slow and expensive.

This pipeline solves that:

1. You drop a `.txt` file (customer review) into an S3 bucket
2. Lambda triggers **automatically** — no manual action needed
3. Amazon Bedrock (Gemma 3 AI model via Bedrock Mantle) reads the review
4. It extracts: **sentiment**, **score**, **urgency level**, **key topics**, **summary**
5. Results are stored in DynamoDB instantly
6. If the review is **negative or urgent** → you get an **email alert** via SNS

**Zero manual work after deployment.**

---

## 🏗️ Architecture

```
You upload review.txt
        │
        ▼
┌─────────────┐
│  Amazon S3  │  ← Stores your review files
└──────┬──────┘
       │ S3 Event (auto-trigger)
       ▼
┌─────────────┐
│ AWS Lambda  │  ← Runs Python code (no server needed)
└──────┬──────┘
       │ API call
       ▼
┌──────────────────┐
│ Amazon Bedrock   │  ← AI model analyzes the review
│ (Gemma 3 4B via  │     Returns JSON: sentiment, urgency,
│  Bedrock Mantle) │     topics, summary
└──────┬───────────┘
       │
       ├──────────────────────────▶ ┌────────────┐
       │                            │  DynamoDB  │ ← Stores all results
       │                            └────────────┘
       │
       └── if negative/urgent ────▶ ┌─────────┐
                                    │   SNS   │ ← Sends you email alert
                                    └─────────┘

CloudWatch monitors everything ──▶ Dashboard + Alarms
```

---

## 🛠️ AWS Services Used

| Service | What it does in this project |
|---|---|
| **Amazon S3** | Stores review `.txt` files, triggers Lambda on upload |
| **AWS Lambda** | Runs Python code serverlessly when review arrives |
| **Amazon Bedrock** | AI inference — Gemma 3 4B model analyzes review text |
| **Amazon Bedrock Mantle** | AWS's newer routing layer for open-weight AI models |
| **Amazon DynamoDB** | Stores structured analysis results (NoSQL, pay-per-use) |
| **Amazon SNS** | Sends email alerts for negative/urgent reviews |
| **Amazon CloudWatch** | Monitors Lambda errors, invocations, creates alarms |
| **AWS CloudFormation** | Deploys ALL above resources in one command (IaC) |
| **AWS IAM** | Manages permissions — least privilege, no admin access |

---

## ✅ Prerequisites — Read Before Starting

### 1. AWS Account
You need an AWS account. Free tier works.
- Sign up: https://aws.amazon.com/free

### 2. AWS CLI Installed on Your Computer
The AWS CLI lets you run AWS commands from your terminal/command prompt.

**Check if already installed:**
```bash
aws --version
```
If you see a version number → you're good. Skip to step 3.

**If not installed:**
- Windows: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Mac: `brew install awscli`
- Linux: `sudo apt install awscli`

### 3. Configure AWS CLI with Your Credentials

You need to connect the CLI to your AWS account.

**Step 1 — Get your Access Keys:**
1. Go to AWS Console → top right → click your name → **Security credentials**
2. Scroll to **Access keys** → click **Create access key**
3. Copy both: **Access Key ID** and **Secret Access Key**

**Step 2 — Run this in your terminal:**
```bash
aws configure
```
It will ask 4 questions:
```
AWS Access Key ID: [paste your key here]
AWS Secret Access Key: [paste your secret here]
Default region name: us-east-1
Default output format: json
```

**Step 3 — Test it works:**
```bash
aws sts get-caller-identity
```
You should see your Account ID. If yes → CLI is ready. ✓

### 4. Supported AWS Regions

This project uses **Amazon Bedrock Mantle** with the Gemma 3 4B model.

⚠️ **Only deploy in these regions** (Gemma 3 is available here):
- `us-east-1` ← recommended
- `us-west-2`
- `eu-west-1`

Do NOT use `ap-south-1` (Mumbai) — Gemma 3 is not available there yet.

---

## 🚀 Deployment — Step by Step

### Step 1 — Clone this repository

Open your terminal (Command Prompt on Windows, Terminal on Mac/Linux):

```bash
git clone https://github.com/akash017kumar/sentiment-detective.git
cd sentiment-detective
```

Don't have Git? Download ZIP instead:
- Click green **Code** button above → **Download ZIP** → extract it → open terminal inside that folder

### Step 2 — Deploy with one command

**On Mac/Linux:**
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh your@email.com us-east-1
```

**On Windows (Command Prompt):**
```bash
aws cloudformation deploy ^
  --template-file cfn/template.yaml ^
  --stack-name "sentiment-detective" ^
  --region "us-east-1" ^
  --parameter-overrides AlertEmail="your@email.com" BedrockRegion="us-east-1" ^
  --capabilities CAPABILITY_NAMED_IAM
```

Replace `your@email.com` with your actual email.

**What happens now:**
```
Waiting for changeset to be created...
Waiting for stack create/update to complete...
Successfully created/updated stack - sentiment-detective   ← you want to see this
```

Takes about **2-3 minutes.**

### Step 3 — Confirm your email

Check your inbox. You'll get an email from **AWS Notifications**.

Click **"Confirm subscription"** — otherwise you won't receive alerts.

### Step 4 — Get your S3 bucket name

```bash
aws cloudformation describe-stacks \
  --stack-name "sentiment-detective" \
  --region "us-east-1" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
  --output text
```

It will print something like:
```
sentiment-detective-content-123456789012
```

Copy that. You'll need it next.

---

## 📤 How to Use — Upload a Review

Create a text file with any customer review content. Example:

**review1.txt:**
```
I ordered this product 2 weeks ago and it still hasn't arrived. 
Customer support is not responding. Very disappointed. 
I want a full refund immediately.
```

Upload it to S3:
```bash
aws s3 cp review1.txt s3://YOUR-BUCKET-NAME/reviews/review1.txt --region us-east-1
```

Replace `YOUR-BUCKET-NAME` with the bucket name from Step 4.

**That's it.** Wait ~10 seconds.

---

## 📊 Check Results in DynamoDB

```bash
aws dynamodb scan \
  --table-name "sentiment-detective-results" \
  --region "us-east-1" \
  --query "Items[*].{File:s3_key.S,Sentiment:sentiment.S,Urgency:urgency_level.S,Score:sentiment_score.S,Summary:summary.S}" \
  --output table
```

You'll see:

```
------------------------------------------------------------------------------------------
|                                         Scan                                           |
+------------------+------------+-----------+--------+----------------------------------+
| File             | Sentiment  | Urgency   | Score  | Summary                          |
+------------------+------------+-----------+--------+----------------------------------+
| reviews/review1  | negative   | high      | -0.9   | Customer demands refund after... |
+------------------+------------+-----------+--------+----------------------------------+
```

---

## 📧 Email Alerts

If a review is **negative** OR urgency is **high/critical** → you get an email automatically:

```
Subject: [Sentiment Detective] HIGH urgency detected

Sentiment: negative
Urgency: high
Topics: delivery delay, refund request
Summary: Customer reports non-delivery and demands immediate refund
File: s3://your-bucket/reviews/review1.txt
```

---

## 🗂️ Project Structure

```
sentiment-detective/
├── cfn/
│   └── template.yaml          ← All 7 AWS resources defined as IaC
├── docs/
│   └── architecture.md        ← Detailed technical decisions
├── lambda/
│   └── handler.py             ← Python Lambda function (the brain)
├── sample-reviews/
│   ├── negative-urgent.txt    ← Test it with this
│   ├── positive-happy.txt     ← And this
│   └── neutral-feedback.txt   ← And this
├── scripts/
│   └── deploy.sh              ← One-command deploy (Mac/Linux)
└── README.md
```

---

## ❌ Troubleshooting

### "Stack is in ROLLBACK_COMPLETE state"
Old failed stack exists. Delete it and retry:
```bash
aws cloudformation delete-stack --stack-name "sentiment-detective" --region "us-east-1"
```
Wait 60 seconds. Then run the deploy command again.

### "Model not found" or Bedrock error
You're in a region where Gemma 3 4B isn't available.
Change region to `us-east-1`:
```bash
aws configure set region us-east-1
```
Then redeploy.

### DynamoDB table shows 0 results after upload
Lambda may have errored. Check logs:
```bash
aws logs tail /aws/lambda/sentiment-detective-analyzer --region us-east-1 --follow
```

### "AccessDenied" error
Your IAM user doesn't have enough permissions. Make sure your AWS user has these policies attached:
- `AmazonS3FullAccess`
- `AWSLambda_FullAccess`
- `AmazonDynamoDBFullAccess`
- `AWSCloudFormationFullAccess`
- `AmazonSNSFullAccess`
- `IAMFullAccess`
- `AmazonBedrockFullAccess`

---

## 🧹 Delete Everything (Clean Up)

To avoid any AWS charges, delete all resources when done:

```bash
# Step 1 — Empty the S3 bucket first (required before deleting stack)
aws s3 rb s3://YOUR-BUCKET-NAME --force --region us-east-1

# Step 2 — Delete the entire CloudFormation stack
aws cloudformation delete-stack --stack-name "sentiment-detective" --region "us-east-1"
```

All 7 resources deleted. Zero ongoing cost.

---

## 💰 Cost Estimate

| Service | Cost for 1,000 reviews |
|---|---|
| Lambda | $0.00 (free tier) |
| Bedrock Gemma 3 4B | ~$0.04 |
| DynamoDB | $0.00 (pay-per-request) |
| S3 | ~$0.01 |
| SNS | $0.00 (first 1,000 emails free) |
| **Total** | **~$0.05** |

---

## 👨‍💻 Author

**Akash Kumar Nahak**
Cloud Operations / DevOps Engineer | AWS Certified AI Practitioner

- GitHub: [github.com/akash017kumar](https://github.com/akash017kumar)
- LinkedIn: [linkedin.com/in/YOUR_LINKEDIN](https://linkedin.com/in/YOUR_LINKEDIN)

---

## 📄 License

MIT License — free to use, modify, and distribute.
