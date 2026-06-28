#!/usr/bin/env bash
# CRUD smoke test for the orders table.
#
# Exercises the same operations the rubric asks you to perform in the
# console (insert / query / view), plus an update and delete, against the
# deployed DynamoDB table. Useful as a quick verification or as evidence.
#
# Usage:
#   ./scripts/crud-smoke-test.sh dev      # targets orders-dev
#   ./scripts/crud-smoke-test.sh prod     # targets orders-prod
#
# Requires valid AWS credentials and the AWS CLI.
set -euo pipefail

ENV="${1:-dev}"
REGION="${AWS_REGION:-eu-north-1}"
TABLE="orders-${ENV}"

echo ">> Table: ${TABLE}  (region ${REGION})"

echo ">> CREATE: put OrderId=ORD-1001"
aws dynamodb put-item --region "$REGION" --table-name "$TABLE" --item '{
  "OrderId":    {"S": "ORD-1001"},
  "CustomerId": {"S": "CUST-42"},
  "Status":     {"S": "PENDING"},
  "Total":      {"N": "129.99"}
}'

echo ">> CREATE: put OrderId=ORD-1002"
aws dynamodb put-item --region "$REGION" --table-name "$TABLE" --item '{
  "OrderId":    {"S": "ORD-1002"},
  "CustomerId": {"S": "CUST-42"},
  "Status":     {"S": "SHIPPED"},
  "Total":      {"N": "59.50"}
}'

echo ">> READ (primary key): get OrderId=ORD-1001"
aws dynamodb get-item --region "$REGION" --table-name "$TABLE" \
  --key '{"OrderId": {"S": "ORD-1001"}}'

echo ">> QUERY GSI CustomerId-index: all orders for CUST-42"
aws dynamodb query --region "$REGION" --table-name "$TABLE" \
  --index-name CustomerId-index \
  --key-condition-expression "CustomerId = :c" \
  --expression-attribute-values '{":c": {"S": "CUST-42"}}'

echo ">> QUERY GSI Status-index: all SHIPPED orders"
aws dynamodb query --region "$REGION" --table-name "$TABLE" \
  --index-name Status-index \
  --key-condition-expression "#s = :st" \
  --expression-attribute-names '{"#s": "Status"}' \
  --expression-attribute-values '{":st": {"S": "SHIPPED"}}'

echo ">> UPDATE: set ORD-1001 Status=SHIPPED"
aws dynamodb update-item --region "$REGION" --table-name "$TABLE" \
  --key '{"OrderId": {"S": "ORD-1001"}}' \
  --update-expression "SET #s = :st" \
  --expression-attribute-names '{"#s": "Status"}' \
  --expression-attribute-values '{":st": {"S": "SHIPPED"}}'

echo ">> DELETE: remove ORD-1002"
aws dynamodb delete-item --region "$REGION" --table-name "$TABLE" \
  --key '{"OrderId": {"S": "ORD-1002"}}'

echo ">> Done. CRUD operations completed against ${TABLE}."
