#!/usr/bin/env bash
# Deploy the bootstrap CloudFormation stack (OIDC, IAM roles, S3 buckets).
#
# Run this once per AWS account before the GitHub Actions pipelines can run.
#
# Usage:
#   ./scripts/deploy-bootstrap.sh
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - Valid AWS credentials with admin/deploy permissions
#   - Set CreateOidcProvider=false below if the account already has a
#     GitHub OIDC provider (token.actions.githubusercontent.com).
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="orders-sam-bootstrap"
TEMPLATE="bootstrap/bootstrap.yaml"

echo ">> Deploying ${STACK_NAME} to ${REGION}"

aws cloudformation deploy \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --parameter-overrides \
    GitHubOrg=alfreddey \
    RepoName=aws-sam-dynamodb \
  --capabilities CAPABILITY_NAMED_IAM

echo ">> Done. Stack: ${STACK_NAME}"
