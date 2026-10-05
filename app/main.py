import json
import os
import boto3
from fastapi import FastAPI, HTTPException

app = FastAPI(title="data-api")
BUCKET = os.environ["BUCKET"]
s3 = boto3.client(
    "s3",
    endpoint_url=os.environ.get("S3_ENDPOINT"),  # unset on real AWS (IRSA creds)
    region_name="us-east-1",
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/objects")
def list_objects():
    resp = s3.list_objects_v2(Bucket=BUCKET)
    return [o["Key"] for o in resp.get("Contents", [])]


@app.put("/objects/{key:path}")
def put_object(key: str, body: dict):
    s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(body).encode())
    return {"stored": key}


@app.get("/objects/{key:path}")
def get_object(key: str):
    try:
        obj = s3.get_object(Bucket=BUCKET, Key=key)
    except s3.exceptions.NoSuchKey:
        raise HTTPException(404, "not found")
    return {"key": key, "body": json.loads(obj["Body"].read())}
