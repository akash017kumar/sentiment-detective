import json
import boto3
import os
import uuid
from datetime import datetime, timezone

s3 = boto3.client("s3")
dynamo = boto3.resource("dynamodb")
sns = boto3.client("sns")

TABLE = os.environ["DYNAMODB_TABLE"]
SNS_ARN = os.environ["SNS_TOPIC_ARN"]
REGION = os.environ["BEDROCK_REGION"]
MODEL = os.environ["MODEL_ID"]

# Uses Amazon Bedrock Mantle endpoint via boto3 bedrock-runtime client
bedrock = boto3.client("bedrock-runtime", region_name=REGION)

PROMPT = """Analyze this customer review. Reply ONLY with valid JSON, nothing else.

Review: {content}

Return exactly this structure:
{{"sentiment":"positive/neutral/negative","sentiment_score":<-1.0 to 1.0>,"key_topics":["topic1","topic2"],"urgency_level":"low/medium/high/critical","summary":"one sentence","action_required":true/false}}"""


def lambda_handler(event, context):
    """
    Triggered by S3 ObjectCreated events.
    Reads .txt review file → calls Bedrock (Gemma 3 4B via Mantle) →
    stores structured result in DynamoDB → sends SNS alert if negative/urgent.
    """
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        print(f"Processing: s3://{bucket}/{key}")

        # 1. Read review from S3
        try:
            content = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8").strip()
            if not content:
                continue
        except Exception as e:
            print(f"ERROR reading S3: {e}")
            continue

        # 2. Call Amazon Bedrock (Gemma 3 4B via Bedrock Mantle)
        try:
            resp = bedrock.converse(
                modelId=MODEL,
                messages=[{
                    "role": "user",
                    "content": [{"text": PROMPT.format(content=content)}]
                }],
                inferenceConfig={"maxTokens": 512, "temperature": 0.1}
            )
            raw = resp["output"]["message"]["content"][0]["text"].strip()

            # Strip markdown code fences if model wraps response
            if raw.startswith("```"):
                raw = raw.split("```")[1]
                if raw.startswith("json"):
                    raw = raw[4:]

            analysis = json.loads(raw.strip())

        except Exception as e:
            print(f"ERROR calling Bedrock: {e}")
            continue

        # 3. Store result in DynamoDB
        item_id = str(uuid.uuid4())
        ts = datetime.now(timezone.utc).isoformat()

        dynamo.Table(TABLE).put_item(Item={
            "id": item_id,
            "timestamp": ts,
            "s3_key": key,
            "sentiment": analysis.get("sentiment", "unknown"),
            "sentiment_score": str(analysis.get("sentiment_score", 0)),
            "key_topics": analysis.get("key_topics", []),
            "urgency_level": analysis.get("urgency_level", "low"),
            "summary": analysis.get("summary", ""),
            "action_required": analysis.get("action_required", False),
            "preview": content[:300]
        })

        print(f"Stored result {item_id} for {key}")

        # 4. Send SNS alert if negative or high urgency
        sentiment = analysis.get("sentiment", "neutral")
        urgency = analysis.get("urgency_level", "low")

        if sentiment == "negative" or urgency in ("high", "critical"):
            sns.publish(
                TopicArn=SNS_ARN,
                Subject=f"[Sentiment Detective] {urgency.upper()} urgency detected",
                Message=(
                    f"Sentiment: {sentiment}\n"
                    f"Urgency: {urgency}\n"
                    f"Topics: {', '.join(analysis.get('key_topics', []))}\n"
                    f"Summary: {analysis.get('summary', '')}\n"
                    f"File: s3://{bucket}/{key}\n"
                    f"Record ID: {item_id}"
                )
            )
            print(f"SNS alert sent for {item_id}")

    return {"statusCode": 200}
