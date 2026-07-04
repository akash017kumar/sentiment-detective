#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Sentiment Detective — One-Shot Deploy Script
# Run this in AWS CloudShell (no local setup needed)
# Usage: ./scripts/deploy.sh your@email.com [region]
# ─────────────────────────────────────────────────────────────

set -euo pipefail

ALERT_EMAIL="${1:-}"
AWS_REGION="${2:-us-east-1}"
STACK_NAME="sentiment-detective"
TEMPLATE="$(dirname "$0")/../cfn/template.yaml"

if [[ -z "$ALERT_EMAIL" ]]; then
  echo "ERROR: Provide your email."
  echo "Usage: $0 your@email.com [region]"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   SENTIMENT DETECTIVE — DEPLOYING...     ║"
echo "╚══════════════════════════════════════════╝"
echo "  Email  : $ALERT_EMAIL"
echo "  Region : $AWS_REGION"
echo ""

# Deploy CloudFormation stack
echo "▸ Deploying stack (takes ~2 min)..."
aws cloudformation deploy \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" \
  --parameter-overrides \
    AlertEmail="$ALERT_EMAIL" \
    BedrockRegion="$AWS_REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

# Get outputs
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
  --output text)

TABLE=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='TableName'].OutputValue" \
  --output text)

# Upload sample reviews
echo ""
echo "▸ Uploading sample reviews..."
for f in sample-reviews/*.txt; do
  fname=$(basename "$f")
  aws s3 cp "$f" "s3://$BUCKET/samples/$fname" --region "$AWS_REGION" --quiet
  echo "  ✓ $fname"
  sleep 2
done

echo ""
echo "▸ Waiting 20s for Lambda to process..."
sleep 20

echo ""
echo "▸ Results in DynamoDB:"
aws dynamodb scan \
  --table-name "$TABLE" \
  --region "$AWS_REGION" \
  --query "Items[*].{File:s3_key.S,Sentiment:sentiment.S,Urgency:urgency_level.S,Score:sentiment_score.S}" \
  --output table

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  DEPLOYED SUCCESSFULLY ✓                             ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  S3 Bucket : %-39s ║\n" "$BUCKET"
printf "║  DynamoDB  : %-39s ║\n" "$TABLE"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Check your email and confirm SNS subscription!      ║"
echo "╚══════════════════════════════════════════════════════╝"
