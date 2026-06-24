# Deploy a DynamoDB Table with AWS SAM

Provisions an Amazon DynamoDB **Orders** table with AWS SAM and deploys it to
**dev** and **prod** through **two separate GitHub Actions pipelines** that
authenticate to AWS with **GitHub OIDC** (no long-lived secrets) and use a
**dedicated S3 artifact bucket per environment**.

## What gets created

| File | Purpose |
|------|---------|
| `template.yaml` | SAM template defining the DynamoDB table (the deployable infra) |
| `samconfig.toml` | Named `dev` / `prod` configs for local `sam deploy` |
| `bootstrap/bootstrap.yaml` | One-time CloudFormation: GitHub OIDC provider, per-env IAM deploy roles, per-env artifact S3 buckets |
| `.github/workflows/deploy-dev.yml` | Dev pipeline — deploys `orders-table-dev` on push to `main` |
| `.github/workflows/deploy-prod.yml` | Prod pipeline — deploys `orders-table-prod` on release tag `v*` / manual dispatch |
| `scripts/crud-smoke-test.sh` | CRUD verification helper (insert/read/query GSIs/update/delete) |

## Table design (`template.yaml`)

| Property | Value | Why |
|----------|-------|-----|
| Billing mode | `PAY_PER_REQUEST` | On-Demand (rubric) |
| Table class | `STANDARD_INFREQUENT_ACCESS` | Non-default storage class (rubric) |
| Primary key | `OrderId` (partition key) | Required primary key |
| Non-key attributes | `CustomerId`, `Status` | The two named attributes |
| GSI 1 | `CustomerId-index` on `CustomerId` | Query orders by customer |
| GSI 2 | `Status-index` on `Status` | Query orders by status |

Table name is environment-suffixed: `orders-dev` / `orders-prod`.

---

## Deployment runbook

Prerequisites: AWS CLI, AWS SAM CLI, and the GitHub CLI (`gh`), all
authenticated. Default region is `us-east-1`.

### 0. Authenticate

```bash
aws sso login            # or however you sign in; confirm with:
aws sts get-caller-identity
gh auth login            # needed to create the repo + set variables
```

### 1. Create the GitHub repo and push

```bash
git init && git add . && git commit -m "SAM DynamoDB table + dev/prod OIDC pipelines"
gh repo create aws-sam-dynamodb --public --source=. --remote=origin --push
```

Note the repo's `owner/name` — you need it for the next step.

### 2. Bootstrap AWS (one time per account)

Creates the OIDC provider, the two deploy roles, and the two artifact buckets.

```bash
aws cloudformation deploy \
  --template-file bootstrap/bootstrap.yaml \
  --stack-name orders-sam-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameter-overrides GitHubOrg=<YOUR_GH_OWNER> RepoName=aws-sam-dynamodb
```

> Already have a GitHub OIDC provider in the account? Add
> `CreateOidcProvider=false` to `--parameter-overrides`.

Grab the outputs (role ARNs + bucket names):

```bash
aws cloudformation describe-stacks --stack-name orders-sam-bootstrap \
  --region us-east-1 --query "Stacks[0].Outputs" --output table
```

### 3. Wire the outputs into GitHub repo variables

The pipelines read these as repo-level **Variables** (not secrets — they are
not sensitive). Replace the values with the bootstrap outputs:

```bash
gh variable set AWS_REGION              --body "us-east-1"
gh variable set AWS_DEV_ROLE_ARN        --body "<DevDeployRoleArn>"
gh variable set AWS_PROD_ROLE_ARN       --body "<ProdDeployRoleArn>"
gh variable set AWS_DEV_ARTIFACT_BUCKET --body "<DevArtifactBucketName>"
gh variable set AWS_PROD_ARTIFACT_BUCKET --body "<ProdArtifactBucketName>"
```

### 4. Create the GitHub Environments

The OIDC trust policies only allow the roles to be assumed from these
environments, so the names must match exactly.

- **development** — used by the dev pipeline (no protection needed).
- **production** — used by the prod pipeline; add a **required reviewer** so
  prod deploys wait for manual approval.

```bash
# environments can be created in the GitHub UI (Settings > Environments),
# or via the API:
gh api -X PUT repos/<owner>/aws-sam-dynamodb/environments/development
gh api -X PUT repos/<owner>/aws-sam-dynamodb/environments/production
```

### 5. Deploy dev

The push in step 1 already triggered `deploy-dev.yml`. Re-run any time with:

```bash
gh workflow run deploy-dev.yml
gh run watch
```

### 6. Deploy prod (explicit promotion)

```bash
git tag v1.0.0 && git push origin v1.0.0   # triggers deploy-prod.yml
# approve the run in the "production" environment when prompted
```

### 7. Verify CRUD

In the **AWS Console** → DynamoDB → Tables → `orders-dev` → *Explore table
items* → *Create item*: add an item (e.g. `OrderId=ORD-1001`,
`CustomerId=CUST-42`, `Status=PENDING`), then query the `CustomerId-index` /
`Status-index` GSIs and view results.

Or run the helper to do the same from the CLI:

```bash
./scripts/crud-smoke-test.sh dev
```

---

## Local deploy (optional, bypasses CI)

```bash
sam build
sam deploy --config-env dev     # after setting s3_bucket in samconfig.toml
sam deploy --config-env prod
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name orders-table-dev  --region us-east-1
aws cloudformation delete-stack --stack-name orders-table-prod --region us-east-1
# bootstrap buckets are RETAINed on stack delete; empty + delete them manually if desired
aws cloudformation delete-stack --stack-name orders-sam-bootstrap --region us-east-1
```
