#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Sentiment Detective — Deploy Script
# Works on Mac and Linux. For Windows use the README commands.
#
# Usage: ./scripts/deploy.sh your@email.com [region]
# Example: ./scripts/deploy.sh john@gmail.com us-east-1
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ── Get inputs ────────────────────────────────────────────────
ALERT_EMAIL="${1:-}"
AWS_REGION="${2:-us-east-1}"
STACK_NAME="sentiment-detective"
TEMPLATE="$(dirname "$0")/../cfn/template.yaml"

# ── Validate email provided ───────────────────────────────────
if [[ -z "$ALERT_EMAIL" ]]; then
  echo ""
  echo "ERROR: No email provided."
  echo ""
  echo "Usage: ./scripts/deploy.sh your@email.com [region]"
  echo "Example: ./scripts/deploy.sh john@gmail.com us-east-1"
  echo ""
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   SENTIMENT DETECTIVE — DEPLOYING        ║"
echo "╚══════════════════════════════════════════╝"
echo "  Alert email : $ALERT_EMAIL"
echo "  AWS Region  : $AWS_REGION"
echo "  Stack name  : $STACK_NAME"
echo ""

# ── Check AWS CLI is configured ───────────────────────────────
echo "▸ Checking AWS credentials..."
aws sts get-caller-identity --region "$AWS_REGION" > /dev/null 2>&1 || {
  echo ""
  echo "ERROR: AWS CLI not configured."
  echo "Run: aws configure"
  echo "Then retry this script."
  exit 1
}
echo "  ✓ AWS credentials OK"

# ── Deploy CloudFormation stack ───────────────────────────────
echo ""
echo "▸ Deploying stack (takes 2-3 minutes)..."
aws cloudformation deploy \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" \
  --parameter-overrides \
    AlertEmail="$ALERT_EMAIL" \
    BedrockRegion="$AWS_REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo "  ✓ Stack deployed"

# ── Get stack outputs ─────────────────────────────────────────
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
  --output text)

TABLE=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='TableName'].OutputValue" \
  --output text)

# ── Upload sample reviews as test ─────────────────────────────
SCRIPT_DIR="$(dirname "$0")"
SAMPLES_DIR="$SCRIPT_DIR/../sample-reviews"

if [ -d "$SAMPLES_DIR" ]; then
  echo ""
  echo "▸ Uploading sample reviews to test pipeline..."
  for f in "$SAMPLES_DIR"/*.txt; do
    fname=$(basename "$f")
    aws s3 cp "$f" "s3://$BUCKET/samples/$fname" \
      --region "$AWS_REGION" --quiet
    echo "  ✓ Uploaded: $fname"
    sleep 2
  done

  echo ""
  echo "▸ Waiting 20 seconds for Lambda to process..."
  sleep 20

  echo ""
  echo "▸ Results in DynamoDB:"
  aws dynamodb scan \
    --table-name "$TABLE" \
    --region "$AWS_REGION" \
    --query "Items[*].{File:s3_key.S,Sentiment:sentiment.S,Urgency:urgency_level.S,Score:sentiment_score.S}" \
    --output table
fi

# ── Print summary ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  DEPLOYED SUCCESSFULLY ✓                                 ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  S3 Bucket  : %-43s ║\n" "$BUCKET"
printf "║  DynamoDB   : %-43s ║\n" "$TABLE"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  IMPORTANT: Check your email and confirm SNS             ║"
echo "║  subscription to receive alerts!                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  TO UPLOAD YOUR OWN REVIEW:                              ║"
printf "║  aws s3 cp review.txt s3://%s/reviews/r.txt\n" "$BUCKET"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  TO DELETE EVERYTHING WHEN DONE:                         ║"
printf "║  aws s3 rb s3://%s --force\n" "$BUCKET"
printf "║  aws cloudformation delete-stack --stack-name %s\n" "$STACK_NAME"
echo "╚══════════════════════════════════════════════════════════╝"
