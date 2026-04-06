# SSL Setup for J2EE App on WebSphere Liberty — AWS ECS Fargate + GitLab CI/CD

**Use Case:** J2EE web application deployed on WebSphere Liberty in AWS ECS Fargate calls an
**internal corporate HTTPS web service** (e.g. address validation API). The service uses a cert
signed by a **private corporate CA** which is not in the JVM's default cacerts — causing SSL
handshake failures across all environments (DEV / TEST / QA / PROD).

**Constraints:**
- Runtime: AWS ECS Fargate (no Docker volume mounts allowed)
- CI/CD: GitLab Pipelines
- Secrets: AWS Secrets Manager (per environment)
- Environments: DEV, TEST, QA, PROD — each deployed to separate AWS accounts or namespaces

---

## Table of Contents

1. [Understanding the Problem](#1-understanding-the-problem)
2. [Understanding SSL Certificate Hierarchy](#2-understanding-ssl-certificate-hierarchy)
3. [Overall Architecture — Fargate + Secrets Manager](#3-overall-architecture--fargate--secrets-manager)
4. [Step 1 — Get the Corporate CA Certs](#4-step-1--get-the-corporate-ca-certs)
5. [Step 2 — Build the Truststore Locally](#5-step-2--build-the-truststore-locally)
6. [Step 3 — Store Truststore in AWS Secrets Manager](#6-step-3--store-truststore-in-aws-secrets-manager)
7. [Step 4 — Custom Entrypoint Script (Decode JKS at Startup)](#7-step-4--custom-entrypoint-script-decode-jks-at-startup)
8. [Step 5 — Dockerfile](#8-step-5--dockerfile)
9. [Step 6 — Configure WebSphere Liberty server.xml](#9-step-6--configure-websphere-liberty-serverxml)
10. [Step 7 — ECS Task Definition](#10-step-7--ecs-task-definition)
11. [Step 8 — IAM Permissions for ECS Task](#11-step-8--iam-permissions-for-ecs-task)
12. [Step 9 — GitLab CI/CD Pipeline](#12-step-9--gitlab-cicd-pipeline)
13. [Debugging & Troubleshooting on Fargate](#13-debugging--troubleshooting-on-fargate)
14. [Quick Checklist](#14-quick-checklist)
15. [Who to Contact in Enterprise](#15-who-to-contact-in-enterprise)

---

## 1. Understanding the Problem

Internal corporate services use SSL certificates signed by a **private corporate CA** that is not
in the JVM's default `cacerts`. Fargate has an additional complication: **no volume mounts** — you
cannot bind-mount a `trust.jks` file at runtime the way you would with plain Docker or Kubernetes.

```
Your Liberty App (ECS Fargate Task)
    └── Makes HTTPS call to internal-address-svc.corp.com
            └── Server presents its corporate-signed leaf cert
                    └── JVM checks: Is this cert's CA in MY truststore?
                            ├── Default cacerts → Corporate CA NOT found ❌
                            │     PKIX path building failed / SSLHandshakeException
                            │
                            └── Custom trust.jks decoded from Secrets Manager → Found ✅
                                  Connection succeeds
```

**The Fargate solution in one sentence:**
> Encode `trust.jks` as base64 → store in AWS Secrets Manager → inject as an environment variable
> into the Fargate task → decode back to a `.jks` file at container startup via an entrypoint script
> → Liberty picks it up.

---

## 2. Understanding SSL Certificate Hierarchy

```
┌──────────────────────────────────────────────────────┐
│                    ROOT CA                           │
│  • Self-signed · managed by corporate PKI/SecOps     │
│  • Never installed on servers · stored offline       │
│  • Valid: 10–20 years                                │
│  e.g. "YourCorp Root CA"                             │
└───────────────────────┬──────────────────────────────┘
                        │ signs
┌───────────────────────▼──────────────────────────────┐
│                INTERMEDIATE CA                       │
│  • Signed by Root CA                                 │
│  • Signs all individual server (leaf) certs          │
│  • Valid: 3–5 years                                  │
│  e.g. "YourCorp Internal Services CA"                │
└────────┬──────────────────┬──────────────┬───────────┘
         │ signs            │ signs        │ signs
┌────────▼────────┐  ┌──────▼──────┐  ┌───▼─────────────┐
│   DEV leaf cert │  │ TEST/QA cert│  │  PROD leaf cert  │
│ dev-svc.corp.com│  │ qa-svc.corp │  │  svc.corp.com    │
│  Valid: 1 year  │  │ Valid: 1 yr │  │  Valid: 1 year   │
└─────────────────┘  └─────────────┘  └──────────────────┘
      LEAF CERTS — DO NOT import into truststore
```

| Cert Layer | Import into trust.jks? | Why |
|---|---|---|
| Root CA | ✅ Yes | Anchors the full chain of trust |
| Intermediate CA | ✅ Yes | Directly signs all environment leaf certs |
| Leaf / Server cert | ❌ Never | Different per environment, expires yearly |

> If all environments use certs signed by the **same corporate CA**, one `trust.jks` works across
> DEV / TEST / QA / PROD. The same base64-encoded secret can be stored in each environment's
> Secrets Manager. Only the keystore (`key.jks`) typically differs per environment.

---

## 3. Overall Architecture — Fargate + Secrets Manager

```
┌─────────────────────────────────────────────────────────────────────┐
│  GitLab CI/CD Pipeline                                              │
│                                                                     │
│  1. Build Docker image (NO certs baked in)                          │
│  2. Push image to Amazon ECR                                        │
│  3. Deploy: update ECS Task Definition → trigger new Fargate task   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  AWS Secrets Manager (per environment account/namespace)            │
│                                                                     │
│  /myapp/dev/trust-jks-b64      ← trust.jks encoded as base64       │
│  /myapp/dev/trust-jks-pass     ← truststore password               │
│  /myapp/dev/key-jks-b64        ← key.jks encoded as base64         │
│  /myapp/dev/key-jks-pass       ← keystore password                 │
└─────────────────────────────────────────────────────────────────────┘
                              │
                ECS injects secrets as env vars at task startup
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ECS Fargate Task                                                   │
│                                                                     │
│  Environment variables at runtime:                                  │
│    TRUST_JKS_B64      = <base64 string from Secrets Manager>        │
│    TRUST_JKS_PASSWORD = <password from Secrets Manager>             │
│    KEY_JKS_B64        = <base64 string from Secrets Manager>        │
│    KEY_JKS_PASSWORD   = <password from Secrets Manager>             │
│                                                                     │
│  entrypoint.sh runs at startup:                                     │
│    echo $TRUST_JKS_B64 | base64 -d > /config/resources/security/trust.jks
│    echo $KEY_JKS_B64   | base64 -d > /config/resources/security/key.jks
│    → then starts Liberty                                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Step 1 — Get the Corporate CA Certs

**Primary path:** Contact your PKI / SecOps team:

> *"Can you provide the Root CA and Intermediate CA certificates for internal corporate services
> in PEM format — ideally as a single `corporate-ca-chain.pem` file?"*

**Manual extraction fallback** (if PKI team unavailable):

```bash
# Pull the full cert chain from the target service
openssl s_client -connect internal-address-svc.corp.com:443 -showcerts 2>/dev/null

# Output explained:
#  Certificate[0]  s:CN=internal-address-svc.corp.com  ← LEAF cert   — SKIP
#  Certificate[1]  s:CN=YourCorp Internal Services CA  ← INTERMEDIATE — SAVE THIS
#  Certificate[2]  s:CN=YourCorp Root CA               ← ROOT CA      — SAVE THIS
#  (Root CA: subject and issuer are identical = self-signed)

# Save Intermediate CA (Certificate[1])
cat > intermediate-ca.pem << 'EOF'
-----BEGIN CERTIFICATE-----
<paste Certificate[1] block here>
-----END CERTIFICATE-----
EOF

# Save Root CA (Certificate[2])
cat > root-ca.pem << 'EOF'
-----BEGIN CERTIFICATE-----
<paste Certificate[2] block here>
-----END CERTIFICATE-----
EOF

# Verify the chain resolves
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem intermediate-ca.pem
# Expected: intermediate-ca.pem: OK
```

---

## 5. Step 2 — Build the Truststore Locally

Do this once. The resulting `trust.jks` is stored in Secrets Manager and reused by all environments.

```bash
# Import Intermediate CA (creates trust.jks if it does not exist)
keytool -import \
  -alias corp-intermediate-ca \
  -file intermediate-ca.pem \
  -keystore trust.jks \
  -storepass changeit \
  -noprompt

# Import Root CA
keytool -import \
  -alias corp-root-ca \
  -file root-ca.pem \
  -keystore trust.jks \
  -storepass changeit \
  -noprompt

# Verify contents
keytool -list -v -keystore trust.jks -storepass changeit | grep -E "Alias|Owner|Issuer|Valid"

# Encode trust.jks as base64 — this is what goes into Secrets Manager
base64 -i trust.jks -o trust-jks.b64       # macOS
# base64 trust.jks > trust-jks.b64         # Linux

# Verify decode round-trip works correctly
base64 -d trust-jks.b64 > trust-decoded.jks
keytool -list -keystore trust-decoded.jks -storepass changeit
# Must show the same two entries as trust.jks
```

---

## 6. Step 3 — Store Truststore in AWS Secrets Manager

Create secrets **per environment** in the appropriate AWS account. Use the AWS CLI or the Console.

### Using AWS CLI

```bash
# Set your environment name and AWS region
ENV=dev
REGION=us-east-1

# Store trust.jks (base64-encoded) as a secret
aws secretsmanager create-secret \
  --name /myapp/${ENV}/trust-jks-b64 \
  --description "Liberty truststore (base64) for ${ENV}" \
  --secret-string file://trust-jks.b64 \
  --region ${REGION}

# Store the truststore password
aws secretsmanager create-secret \
  --name /myapp/${ENV}/trust-jks-pass \
  --description "Liberty truststore password for ${ENV}" \
  --secret-string "changeit" \
  --region ${REGION}

# Store key.jks (base64-encoded) — generate per environment or use same for non-prod
base64 -i key.jks -o key-jks.b64
aws secretsmanager create-secret \
  --name /myapp/${ENV}/key-jks-b64 \
  --description "Liberty keystore (base64) for ${ENV}" \
  --secret-string file://key-jks.b64 \
  --region ${REGION}

# Store the keystore password
aws secretsmanager create-secret \
  --name /myapp/${ENV}/key-jks-pass \
  --description "Liberty keystore password for ${ENV}" \
  --secret-string "mykeystorepass" \
  --region ${REGION}

# Repeat for test, qa, prod — changing ENV= each time
# For prod: use strong passwords and restrict IAM access to SecOps only
```

### Updating an existing secret (e.g. after CA cert rotation)

```bash
aws secretsmanager update-secret \
  --secret-id /myapp/${ENV}/trust-jks-b64 \
  --secret-string file://trust-jks.b64 \
  --region ${REGION}
```

### Secret naming convention

```
/myapp/dev/trust-jks-b64        ← DEV truststore base64
/myapp/dev/trust-jks-pass       ← DEV truststore password
/myapp/dev/key-jks-b64          ← DEV keystore base64
/myapp/dev/key-jks-pass         ← DEV keystore password

/myapp/test/trust-jks-b64
/myapp/test/trust-jks-pass
...

/myapp/qa/trust-jks-b64
/myapp/qa/trust-jks-pass
...

/myapp/prod/trust-jks-b64       ← Managed by SecOps
/myapp/prod/trust-jks-pass      ← Managed by SecOps
/myapp/prod/key-jks-b64         ← Managed by SecOps
/myapp/prod/key-jks-pass        ← Managed by SecOps
```

---

## 7. Step 4 — Custom Entrypoint Script (Decode JKS at Startup)

Since Fargate cannot mount volumes, the JKS files must be written to the container's **ephemeral
filesystem** at startup. This script decodes the base64 env vars and writes the JKS files before
Liberty starts.

Create `entrypoint.sh` in your project root:

```bash
#!/bin/bash
set -e

echo "=== SSL Setup: Decoding keystores from environment ==="

# Create the security directory if it does not exist
mkdir -p /config/resources/security

# Decode trust.jks from base64 environment variable
if [ -z "${TRUST_JKS_B64}" ]; then
  echo "ERROR: TRUST_JKS_B64 environment variable is not set. Cannot start."
  exit 1
fi
echo "${TRUST_JKS_B64}" | base64 -d > /config/resources/security/trust.jks
echo "  trust.jks written successfully."

# Decode key.jks from base64 environment variable
if [ -z "${KEY_JKS_B64}" ]; then
  echo "ERROR: KEY_JKS_B64 environment variable is not set. Cannot start."
  exit 1
fi
echo "${KEY_JKS_B64}" | base64 -d > /config/resources/security/key.jks
echo "  key.jks written successfully."

# Verify the decoded trust.jks is a valid JKS (fail fast before Liberty starts)
keytool -list \
  -keystore /config/resources/security/trust.jks \
  -storepass "${TRUST_JKS_PASSWORD}" \
  -noprompt > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "ERROR: trust.jks validation failed — check TRUST_JKS_B64 and TRUST_JKS_PASSWORD."
  exit 1
fi
echo "  trust.jks verified successfully."

echo "=== SSL Setup complete. Starting WebSphere Liberty... ==="

# Hand off to the Liberty startup command
exec /opt/ibm/wlp/bin/server run defaultServer
```

Make it executable before adding to Docker:

```bash
chmod +x entrypoint.sh
```

---

## 8. Step 5 — Dockerfile

The Dockerfile is **identical for all environments**. No certs are baked in — the entrypoint script
handles everything at runtime.

```dockerfile
FROM icr.io/appcafe/websphere-liberty:kernel-java17-openj9-ubi

# Copy application WAR
COPY --chown=1001:0 myapp.war /config/apps/

# Copy Liberty server configuration (same for all environments)
COPY --chown=1001:0 server.xml /config/

# Copy the entrypoint script that decodes JKS files at container startup
COPY --chown=1001:0 entrypoint.sh /opt/entrypoint.sh

# Install Liberty features declared in server.xml
RUN features.sh

# Switch to Liberty user
USER 1001

# Override the default Liberty entrypoint with our custom startup script
ENTRYPOINT ["/opt/entrypoint.sh"]
```

> **No `COPY` for any `.jks` files.** The entrypoint script writes them at runtime from
> `TRUST_JKS_B64` and `KEY_JKS_B64` environment variables injected by ECS from Secrets Manager.

---

## 9. Step 6 — Configure WebSphere Liberty server.xml

The same `server.xml` is used across all environments. All sensitive values use `${env.VAR}` syntax.

```xml
<server>

    <featureManager>
        <!-- Required for outbound SSL support -->
        <feature>ssl-1.0</feature>
        <feature>transportSecurity-1.0</feature>

        <!-- Your existing application features -->
        <feature>servlet-4.0</feature>
        <feature>jaxrs-2.1</feature>
        <feature>jndi-1.0</feature>
    </featureManager>

    <!--
        Liberty's own identity keystore.
        Written to disk at startup by entrypoint.sh from KEY_JKS_B64 env var.
    -->
    <keyStore id="defaultKeyStore"
              location="${server.config.dir}/resources/security/key.jks"
              password="${env.KEY_JKS_PASSWORD}" />

    <!--
        Truststore containing corporate Root CA and Intermediate CA.
        Written to disk at startup by entrypoint.sh from TRUST_JKS_B64 env var.
    -->
    <keyStore id="outboundTrustStore"
              location="${server.config.dir}/resources/security/trust.jks"
              password="${env.TRUST_JKS_PASSWORD}" />

    <!--
        SSL config wiring both keystores together.
        TLSv1.2 minimum — change to TLSv1.3 if the internal service requires it.
    -->
    <ssl id="defaultSSLConfig"
         keyStoreRef="defaultKeyStore"
         trustStoreRef="outboundTrustStore"
         sslProtocol="TLSv1.2" />

    <!--
        Apply SSL config to all outbound HTTPS connections.
        To restrict to specific internal hosts only:
        <outboundConnection host="internal-address-svc.corp.com" sslRef="defaultSSLConfig" />
    -->
    <outboundConnection host="*" sslRef="defaultSSLConfig" />

</server>
```

---

## 10. Step 7 — ECS Task Definition

ECS Task Definitions reference Secrets Manager ARNs directly. ECS fetches the secrets and injects
them as environment variables **before** the container starts — your entrypoint script then uses them.

```json
{
  "family": "myapp-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "myapp",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest",
      "portMappings": [
        { "containerPort": 9080, "protocol": "tcp" },
        { "containerPort": 9443, "protocol": "tcp" }
      ],
      "secrets": [
        {
          "name": "TRUST_JKS_B64",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:/myapp/dev/trust-jks-b64"
        },
        {
          "name": "TRUST_JKS_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:/myapp/dev/trust-jks-pass"
        },
        {
          "name": "KEY_JKS_B64",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:/myapp/dev/key-jks-b64"
        },
        {
          "name": "KEY_JKS_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:/myapp/dev/key-jks-pass"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/myapp-dev",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:9080/myapp/health || exit 1"],
        "interval": 30,
        "timeout": 10,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

> The `secrets` block in the task definition is what tells ECS to fetch values from Secrets Manager
> and inject them as environment variables. The container never touches Secrets Manager directly —
> the ECS agent does it on behalf of the task using the `executionRoleArn`.

---

## 11. Step 8 — IAM Permissions for ECS Task

Two IAM roles are needed:

### executionRole — used by ECS agent to start the task

This role needs permission to read secrets from Secrets Manager so it can inject them as env vars.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-1:123456789012:secret:/myapp/dev/*"
      ]
    },
    {
      "Sid": "AllowECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

### taskRole — used by the running application

If your application code itself needs to call AWS services (e.g. S3, DynamoDB), add those
permissions here. For the SSL setup, this role does not need Secrets Manager access — the
execution role already handles that at startup.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AppPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "dynamodb:Query"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Scope secrets by environment:** For PROD, restrict the `executionRole` to only
> `/myapp/prod/*` ARNs. Never give DEV execution roles access to PROD secrets.

---

## 12. Step 9 — GitLab CI/CD Pipeline

The pipeline builds one image, pushes to ECR, and deploys to the correct environment by updating
the ECS Task Definition and triggering a new deployment.

### Repository structure

```
myapp/
├── src/
├── server.xml
├── entrypoint.sh
├── Dockerfile
└── .gitlab-ci.yml
```

### GitLab CI/CD Variables (set in GitLab → Settings → CI/CD → Variables)

```
Variable Name              Scope         Value
─────────────────────────────────────────────────────────────────────────
AWS_ACCOUNT_ID_DEV         dev branch    123456789012
AWS_ACCOUNT_ID_TEST        test branch   234567890123
AWS_ACCOUNT_ID_QA          qa branch     345678901234
AWS_ACCOUNT_ID_PROD        main branch   456789012345
AWS_REGION                 all           us-east-1
ECR_REPO_NAME              all           myapp
AWS_ROLE_ARN_DEV           all           arn:aws:iam::123456789012:role/GitLabDeployRole
AWS_ROLE_ARN_PROD          all           arn:aws:iam::456789012345:role/GitLabDeployRole
```

> Use GitLab's **Protected Variables** for PROD values so only protected branches can access them.

### `.gitlab-ci.yml`

```yaml
stages:
  - build
  - deploy-dev
  - deploy-test
  - deploy-qa
  - deploy-prod

variables:
  AWS_REGION: "us-east-1"
  ECR_REPO_NAME: "myapp"

# ─── Reusable: AWS login + ECR auth ──────────────────────────────────────────
.aws_login: &aws_login
  before_script:
    - apt-get update -qq && apt-get install -y -qq awscli jq curl > /dev/null
    - |
      # Assume the deploy role for the target environment via OIDC or IAM credentials
      CREDS=$(aws sts assume-role \
        --role-arn ${AWS_ROLE_ARN} \
        --role-session-name gitlab-deploy-${CI_PIPELINE_ID} \
        --output json)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
    - aws ecr get-login-password --region ${AWS_REGION} |
        docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# ─── BUILD ────────────────────────────────────────────────────────────────────
build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    # Build once — no environment-specific content, no certs
    - docker build -t ${ECR_REPO_NAME}:${CI_COMMIT_SHA} .
    # Tag with commit SHA and also as 'latest'
    - docker tag ${ECR_REPO_NAME}:${CI_COMMIT_SHA}
        ${AWS_ACCOUNT_ID_DEV}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${CI_COMMIT_SHA}
    - docker tag ${ECR_REPO_NAME}:${CI_COMMIT_SHA}
        ${AWS_ACCOUNT_ID_DEV}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest
    # Login to DEV ECR and push (image is pulled by other envs from same ECR or promoted)
    - aws ecr get-login-password --region ${AWS_REGION} |
        docker login --username AWS --password-stdin
        ${AWS_ACCOUNT_ID_DEV}.dkr.ecr.${AWS_REGION}.amazonaws.com
    - docker push ${AWS_ACCOUNT_ID_DEV}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${CI_COMMIT_SHA}
    - docker push ${AWS_ACCOUNT_ID_DEV}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest
  only:
    - merge_requests
    - main
    - dev

# ─── DEPLOY TEMPLATE (reused per environment) ─────────────────────────────────
.deploy_template: &deploy_template
  image: registry.gitlab.com/gitlab-org/cloud-deploy/aws-base:latest
  script:
    - |
      # Update the ECS Task Definition to use the new image SHA
      # Fetch current task definition
      TASK_DEF=$(aws ecs describe-task-definition \
        --task-definition myapp-task-${ENV} \
        --region ${AWS_REGION} \
        --output json | jq '.taskDefinition')

      # Update image to the new commit SHA
      NEW_TASK_DEF=$(echo $TASK_DEF | jq \
        --arg IMAGE "${ECR_URL}/${ECR_REPO_NAME}:${CI_COMMIT_SHA}" \
        '.containerDefinitions[0].image = $IMAGE |
         del(.taskDefinitionArn, .revision, .status,
             .requiresAttributes, .compatibilities,
             .registeredAt, .registeredBy)')

      # Register the updated task definition
      NEW_TASK_ARN=$(aws ecs register-task-definition \
        --region ${AWS_REGION} \
        --cli-input-json "$NEW_TASK_DEF" \
        --output json | jq -r '.taskDefinition.taskDefinitionArn')

      echo "Registered new task definition: ${NEW_TASK_ARN}"

      # Update the ECS service to use the new task definition
      aws ecs update-service \
        --cluster myapp-cluster-${ENV} \
        --service myapp-service-${ENV} \
        --task-definition ${NEW_TASK_ARN} \
        --force-new-deployment \
        --region ${AWS_REGION}

      echo "Deployment triggered for ${ENV}. Waiting for service stability..."

      # Wait for deployment to complete (timeout: 10 minutes)
      aws ecs wait services-stable \
        --cluster myapp-cluster-${ENV} \
        --services myapp-service-${ENV} \
        --region ${AWS_REGION}

      echo "Deployment to ${ENV} complete."

# ─── DEPLOY DEV ───────────────────────────────────────────────────────────────
deploy-dev:
  stage: deploy-dev
  <<: *deploy_template
  variables:
    ENV: dev
    AWS_ROLE_ARN: ${AWS_ROLE_ARN_DEV}
    ECR_URL: ${AWS_ACCOUNT_ID_DEV}.dkr.ecr.${AWS_REGION}.amazonaws.com
  only:
    - dev

# ─── DEPLOY TEST ──────────────────────────────────────────────────────────────
deploy-test:
  stage: deploy-test
  <<: *deploy_template
  variables:
    ENV: test
    AWS_ROLE_ARN: ${AWS_ROLE_ARN_TEST}
    ECR_URL: ${AWS_ACCOUNT_ID_TEST}.dkr.ecr.${AWS_REGION}.amazonaws.com
  only:
    - dev
  when: manual    # Requires manual approval to promote to TEST

# ─── DEPLOY QA ────────────────────────────────────────────────────────────────
deploy-qa:
  stage: deploy-qa
  <<: *deploy_template
  variables:
    ENV: qa
    AWS_ROLE_ARN: ${AWS_ROLE_ARN_QA}
    ECR_URL: ${AWS_ACCOUNT_ID_QA}.dkr.ecr.${AWS_REGION}.amazonaws.com
  only:
    - main
  when: manual

# ─── DEPLOY PROD ──────────────────────────────────────────────────────────────
deploy-prod:
  stage: deploy-prod
  <<: *deploy_template
  variables:
    ENV: prod
    AWS_ROLE_ARN: ${AWS_ROLE_ARN_PROD}
    ECR_URL: ${AWS_ACCOUNT_ID_PROD}.dkr.ecr.${AWS_REGION}.amazonaws.com
  only:
    - main
  when: manual    # Always manual for PROD — requires explicit human approval
  environment:
    name: production
    url: https://myapp.corp.com
```

---

## 13. Debugging & Troubleshooting on Fargate

Fargate has no SSH — all debugging is via CloudWatch Logs and ECS Exec.

### Enable ECS Exec (one-time setup per cluster/service)

```bash
# Enable ECS Exec on your service
aws ecs update-service \
  --cluster myapp-cluster-dev \
  --service myapp-service-dev \
  --enable-execute-command \
  --region us-east-1

# Shell into a running Fargate task (requires SSM agent in the image)
TASK_ARN=$(aws ecs list-tasks \
  --cluster myapp-cluster-dev \
  --service-name myapp-service-dev \
  --output text --query 'taskArns[0]')

aws ecs execute-command \
  --cluster myapp-cluster-dev \
  --task ${TASK_ARN} \
  --container myapp \
  --interactive \
  --command "/bin/bash"
```

### Verify JKS files were decoded correctly at startup

```bash
# Inside the container via ECS Exec:

# Check the files exist and have non-zero size
ls -lh /config/resources/security/

# Verify trust.jks is valid and contains the expected CA entries
keytool -list -v \
  -keystore /config/resources/security/trust.jks \
  -storepass ${TRUST_JKS_PASSWORD} \
  | grep -E "Alias|Owner|Issuer|Valid"

# Test HTTPS connectivity to the internal service from inside the task
curl -v https://internal-address-svc.corp.com
# curl succeeds but Java fails → truststore issue
# curl also fails → network/VPC/security group issue
```

### Check CloudWatch Logs for startup errors

The entrypoint script logs to stdout which flows to CloudWatch via the awslogs driver:

```
Log group:  /ecs/myapp-dev
Log stream: ecs/myapp/<task-id>

Look for:
  "=== SSL Setup: Decoding keystores from environment ==="  ← entrypoint started
  "trust.jks written successfully."                         ← decode OK
  "trust.jks verified successfully."                        ← JKS valid
  "=== SSL Setup complete. Starting WebSphere Liberty... ==="

If you see:
  "ERROR: TRUST_JKS_B64 environment variable is not set"
    → Secret not wired in task definition secrets block
    → Check secret ARN in task definition is correct
    → Check executionRole has secretsmanager:GetSecretValue on that ARN

  "ERROR: trust.jks validation failed"
    → base64 encoding/decoding issue — re-encode trust.jks and update the secret
    → Password mismatch — verify TRUST_JKS_PASSWORD matches what was used in keytool

  "PKIX path building failed" in Liberty logs
    → trust.jks decoded correctly but missing the right CA cert
    → Re-check which cert chain index you extracted (must be [1] and [2], not [0])
```

### Enable Liberty SSL debug logging temporarily

Add to `server.xml` for a specific deployment, then remove after diagnosis:

```xml
<logging traceSpecification="SSL=all:handshake=all" />
```

Or set as an environment variable in the task definition:

```json
{
  "name": "WLP_LOGGING_CONSOLE_LOGLEVEL",
  "value": "DEBUG"
}
```

### Common Errors and Fixes

| Error | Root Cause | Fix |
|---|---|---|
| `TRUST_JKS_B64 is not set` | Secret not in task definition or wrong ARN | Check `secrets` block in task definition — verify ARN matches Secrets Manager |
| `trust.jks validation failed` | Bad base64 encoding or wrong password | Re-encode with `base64 -i trust.jks` and update the secret. Verify password |
| `PKIX path building failed` | Wrong cert imported — likely the leaf cert | Re-extract: import Certificate[1] and [2] only, never Certificate[0] |
| `SSLHandshakeException: handshake_failure` | TLS protocol mismatch | Change `sslProtocol` in server.xml to `TLSv1.3` — ask service team what they support |
| `hostname in certificate didn't match` | URL uses IP or wrong hostname | Use the exact hostname matching the cert CN or SAN |
| `curl fails inside container` | VPC/security group blocking outbound | Check security group outbound rules and VPC routing — not a cert issue |
| Task fails to start | entrypoint.sh not executable | Ensure `chmod +x entrypoint.sh` before Docker build |
| Task fails to start | executionRole missing Secrets Manager permission | Add `secretsmanager:GetSecretValue` to the executionRole IAM policy |
| Secret fetch fails at ECS startup | KMS key access denied | If secret is encrypted with a CMK, add `kms:Decrypt` to executionRole |

---

## 14. Quick Checklist

### One-time setup (done by dev or SecOps)

- [ ] Obtained Root CA and Intermediate CA PEM files from PKI team
- [ ] Built `trust.jks` with both CA certs via `keytool -import` (NOT the leaf cert)
- [ ] Verified truststore with `keytool -list`
- [ ] Encoded `trust.jks` to base64 and verified decode round-trip
- [ ] Stored base64-encoded `trust.jks` and password in Secrets Manager per environment
- [ ] Stored base64-encoded `key.jks` and password in Secrets Manager per environment

### Dockerfile / entrypoint

- [ ] `entrypoint.sh` created and is executable (`chmod +x`)
- [ ] `entrypoint.sh` validates env vars exist before decoding
- [ ] `entrypoint.sh` validates decoded JKS is readable with `keytool -list`
- [ ] Dockerfile uses `ENTRYPOINT ["/opt/entrypoint.sh"]`
- [ ] Dockerfile has **no** `COPY` for any `.jks` files
- [ ] Dockerfile is identical across all environments

### server.xml

- [ ] `ssl-1.0` and `transportSecurity-1.0` features added
- [ ] `<keyStore id="outboundTrustStore">` pointing to `trust.jks`
- [ ] `<ssl id="defaultSSLConfig">` referencing both keystores
- [ ] `<outboundConnection host="*">` added
- [ ] All passwords use `${env.VAR_NAME}` — nothing hardcoded

### ECS Task Definition

- [ ] `secrets` block references the correct Secrets Manager ARNs per environment
- [ ] `executionRoleArn` has `secretsmanager:GetSecretValue` for those ARNs
- [ ] If CMK-encrypted secrets: `executionRole` also has `kms:Decrypt`
- [ ] `taskRoleArn` is separate from `executionRoleArn`
- [ ] CloudWatch log group exists for the environment

### GitLab CI/CD

- [ ] `AWS_ROLE_ARN_*` variables set per environment in GitLab CI/CD settings
- [ ] PROD variables marked as **Protected** in GitLab
- [ ] Build stage produces one image with no env-specific content
- [ ] Deploy stages use `when: manual` for TEST, QA, PROD
- [ ] Pipeline updates the task definition image tag and triggers `update-service`

### IAM

- [ ] `executionRole` can read only `/myapp/${env}/*` secrets (scoped per environment)
- [ ] DEV `executionRole` cannot read PROD secrets
- [ ] PROD secrets managed exclusively by SecOps

---

## 15. Who to Contact in Enterprise

| Team | What to Ask |
|---|---|
| **PKI / SecOps** | *"Can you provide Root CA and Intermediate CA certs for internal services as `corporate-ca-chain.pem`?"* |
| **PKI / SecOps** | *"Does our network do TLS inspection / SSL proxy? If yes, which CA cert does the proxy use?"* |
| **Cloud / AWS Platform** | *"What IAM roles should our ECS tasks use to read from Secrets Manager in each environment?"* |
| **Cloud / AWS Platform** | *"Are our Secrets Manager secrets encrypted with a CMK? If yes, what is the KMS key ARN?"* |
| **DevOps / SRE** | *"How does our GitLab runner authenticate to AWS — OIDC, IAM user, or assumed role?"* |
| **Network / VPC team** | *"Do our Fargate tasks in the private subnet have a NAT gateway or VPC endpoint to reach the internal service?"* |
| **Target service owner** | *"What TLS version do all your environments support — TLSv1.2 or TLSv1.3?"* |
| **Target service owner** | *"Do all your environment endpoints share the same corporate CA?"* |

---

## Summary — The Golden Rules for Fargate

```
✅  Always  Encode trust.jks as base64 → store in AWS Secrets Manager per environment
✅  Always  Let ECS inject secrets as environment variables via the task definition secrets block
✅  Always  Decode JKS files in entrypoint.sh at container startup before Liberty starts
✅  Always  Validate the decoded JKS with keytool in entrypoint.sh (fail fast)
✅  Always  Scope executionRole IAM policy to /myapp/${env}/* only — never cross-environment
✅  Always  Build one Docker image — no environment-specific content, no certs baked in
✅  Always  Use when: manual in GitLab for TEST / QA / PROD deployments

❌  Never   Copy .jks files into the Docker image
❌  Never   Hardcode passwords in server.xml, Dockerfile, or GitLab CI variables (use Secrets Manager)
❌  Never   Import the leaf/server cert — import Intermediate CA + Root CA only
❌  Never   Give DEV execution roles access to PROD secrets in Secrets Manager
❌  Never   Store trust.jks or passwords in GitLab CI/CD variables — use Secrets Manager
```
