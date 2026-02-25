# Oracle On-Prem → Amazon RDS Oracle Migration Runbook

> **Purpose:** Step-by-step procedure to migrate Oracle schemas and data from on-premises Oracle to Amazon RDS for Oracle using Data Pump and S3 Integration.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Execution Options](#execution-options)
   - [Option A — GitLab CI/CD Pipeline](#option-a--gitlab-cicd-pipeline)
   - [Option B — Manual from Local PC via SSH Tunnel](#option-b--manual-from-local-pc-via-ssh-tunnel)
3. [Prerequisites](#prerequisites)
4. [Step 1 — Export from On-Prem](#step-1--export-from-on-prem)
5. [Step 2 — Upload to S3](#step-2--upload-to-s3)
6. [Step 3 — Download into RDS](#step-3--download-into-rds)
7. [Step 4 — Import into RDS](#step-4--import-into-rds)
8. [Post-Import Validation](#post-import-validation)
9. [Cutover Checklist](#cutover-checklist)
10. [Security Best Practices](#security-best-practices)

---

## Architecture Overview

### Data Flow

```
On-Prem Oracle
     │
     │  expdp (Data Pump Export)
     ▼
Dump Files (.dmp)
     │
     │  aws s3 sync
     ▼
Amazon S3 (Staging Bucket)
     │
     │  rdsadmin.rdsadmin_s3_tasks.download_from_s3
     ▼
RDS DATA_PUMP_DIR
     │
     │  impdp (Data Pump Import)
     ▼
Amazon RDS for Oracle
```

### Execution Topology

Two options are supported for executing the RDS-side steps (Steps 3 & 4). Choose based on your environment and team preference.

```
┌─────────────────────────────────────────────────────────────┐
│  Option A — GitLab CI/CD                                    │
│                                                             │
│  GitLab Runner ──SSH──► Bastion Host ──► RDS Oracle         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  Option B — Manual from Local PC                            │
│                                                             │
│  Local PC ──SSH Tunnel──► Bastion Host ──► RDS Oracle       │
│  (SQL*Plus / impdp run locally over the tunnel)             │
└─────────────────────────────────────────────────────────────┘
```

**Legend:**
- `expdp` export is executed on-prem, typically during the downtime window.
- Dump files are uploaded to an Amazon S3 staging prefix.
- RDS downloads dump files from S3 into `DATA_PUMP_DIR` using the `rdsadmin` stored procedure.
- SQL*Plus and `impdp` are executed either via GitLab CI/CD (Option A) or directly from a local PC through an SSH tunnel (Option B).

---

## Execution Options

The core migration steps (export, S3 upload, S3 download into RDS, import) are identical regardless of option. Only the **how you connect and run** the RDS-side commands differs.

| | Option A — GitLab CI/CD | Option B — Manual from Local PC |
|---|---|---|
| **Best for** | Repeatable, audited, team-driven migrations | Ad-hoc runs, one-off migrations, dev/test |
| **Tooling needed** | GitLab Runner with SSH key to bastion | Oracle Instant Client + SSH on local machine |
| **Auditability** | Full pipeline logs in GitLab | Manual — engineer responsible for logging |
| **Credential handling** | GitLab CI/CD masked variables | Local `.env` file or shell export (ephemeral) |
| **Connection method** | GitLab Runner SSHes into bastion; runs commands there | SSH tunnel from PC → bastion → RDS |

---

### Option A — GitLab CI/CD Pipeline

#### How it works

GitLab Runner SSHes into the bastion host and executes SQL*Plus and `impdp` commands remotely. All steps are defined in `.gitlab-ci.yml` and secrets are stored as GitLab CI/CD masked variables.

#### Sample `.gitlab-ci.yml`

```yaml
stages:
  - export
  - upload
  - rds-download
  - rds-import
  - validate

variables:
  S3_BUCKET: "my-migration-bucket"
  S3_PREFIX: "oracle/prod-cutover/"
  RDS_ENDPOINT: "mydb.xxxx.us-east-1.rds.amazonaws.com"
  RDS_PORT: "1521"
  RDS_SID: "ORCL"

rds-download:
  stage: rds-download
  script:
    - |
      ssh -o StrictHostKeyChecking=no -i $BASTION_KEY ec2-user@$BASTION_HOST "
        sqlplus ${RDS_MASTER_USER}/${RDS_PASSWORD}@//${RDS_ENDPOINT}:${RDS_PORT}/${RDS_SID} <<EOF
        SET SERVEROUTPUT ON
        DECLARE
          l_task_id VARCHAR2(100);
        BEGIN
          l_task_id := rdsadmin.rdsadmin_s3_tasks.download_from_s3(
            p_bucket_name    => '${S3_BUCKET}',
            p_s3_prefix      => '${S3_PREFIX}',
            p_directory_name => 'DATA_PUMP_DIR'
          );
          DBMS_OUTPUT.put_line('TASK_ID=' || l_task_id);
        END;
        /
        EXIT;
        EOF
      "

rds-import:
  stage: rds-import
  script:
    - |
      ssh -o StrictHostKeyChecking=no -i $BASTION_KEY ec2-user@$BASTION_HOST "
        impdp ${RDS_MASTER_USER}/${RDS_PASSWORD}@//${RDS_ENDPOINT}:${RDS_PORT}/${RDS_SID} \
          directory=DATA_PUMP_DIR \
          dumpfile=app_%U.dmp \
          logfile=app_import.log \
          parallel=8 \
          schemas=APP \
          transform=segment_attributes:n \
          exclude=statistics
      "
  needs: ["rds-download"]
```

> ⚠️ **Security:** Store `RDS_PASSWORD`, `RDS_MASTER_USER`, and `BASTION_KEY` as **masked** GitLab CI/CD variables. Never commit them into the repository.

---

### Option B — Manual from Local PC via SSH Tunnel

#### How it works

An SSH tunnel is established from the local PC through the bastion host to the RDS endpoint. SQL*Plus and `impdp` then run **locally** on the PC, connecting via `localhost` as if they were directly connected to RDS.

#### Step B-1 — Install Oracle Instant Client (Local PC)

Download and install Oracle Instant Client matching your RDS Oracle version.

```bash
# macOS (Homebrew)
brew install instantclient-basic instantclient-tools

# Linux (RPM-based)
sudo rpm -ivh oracle-instantclient-basic-*.rpm
sudo rpm -ivh oracle-instantclient-tools-*.rpm

# Verify
sqlplus -V
impdp -V
```

#### Step B-2 — Open SSH Tunnel via Bastion

Open a persistent SSH tunnel that forwards a local port to the RDS endpoint through the bastion host.

```bash
ssh -N -L 1521:<rds-endpoint>:1521 \
    -i ~/.ssh/bastion-key.pem \
    ec2-user@<bastion-public-ip> \
    -o ServerAliveInterval=60 \
    -o ExitOnForwardFailure=yes
```

> 💡 Run this in a **dedicated terminal tab** — keep it open for the duration of the migration. The `-N` flag means no remote command is executed; the tunnel is the only purpose.

| SSH Flag | Purpose |
|---|---|
| `-N` | No remote command — tunnel only |
| `-L 1521:<rds>:1521` | Forward local port 1521 to RDS via bastion |
| `-o ServerAliveInterval=60` | Prevent tunnel from dropping during long imports |
| `-o ExitOnForwardFailure=yes` | Fail fast if the port is already in use |

#### Step B-3 — Configure Local tnsnames.ora (Optional but Recommended)

Add an entry to your local `$ORACLE_HOME/network/admin/tnsnames.ora` (or `~/.tnsnames.ora`):

```
RDS_TUNNEL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 127.0.0.1)(PORT = 1521))
    (CONNECT_DATA =
      (SID = ORCL)
    )
  )
```

This lets you use the alias `RDS_TUNNEL` instead of repeating the full EZConnect string in every command.

#### Step B-4 — Test Connection

```bash
sqlplus master_user/password@//127.0.0.1:1521/ORCL
# or using tnsnames alias:
sqlplus master_user/password@RDS_TUNNEL
```

#### Step B-5 — Run S3 Download Procedure Locally

With the tunnel open, run SQL*Plus from your local PC — it connects through `127.0.0.1:1521` which is forwarded to RDS via the bastion.

```sql
SET SERVEROUTPUT ON
DECLARE
  l_task_id VARCHAR2(100);
BEGIN
  l_task_id := rdsadmin.rdsadmin_s3_tasks.download_from_s3(
    p_bucket_name    => '<bucket>',
    p_s3_prefix      => 'oracle/prod-cutover/',
    p_directory_name => 'DATA_PUMP_DIR'
  );
  DBMS_OUTPUT.put_line('TASK_ID=' || l_task_id);
END;
/
```

#### Step B-6 — Run Import from Local PC

```bash
impdp master_user/password@//127.0.0.1:1521/ORCL \
  directory=DATA_PUMP_DIR \
  dumpfile=app_%U.dmp \
  logfile=app_import.log \
  parallel=8 \
  schemas=APP \
  transform=segment_attributes:n \
  exclude=statistics
```

> ⚠️ **Important:** `DATA_PUMP_DIR` always refers to the directory **on the RDS instance**, not your local PC. The dump files must already have been downloaded into RDS via Step B-5 before running `impdp`.

> 💡 **Tip — Keep a local log:** Redirect `impdp` output to a local log file for your own records:
> ```bash
> impdp ... 2>&1 | tee ~/migration-$(date +%Y%m%d-%H%M%S).log
> ```

---

## Prerequisites

### Common Prerequisites (Both Options)

| Requirement | Details |
|---|---|
| RDS Oracle instance | Must have `S3_INTEGRATION` option enabled |
| IAM Role | Attached to RDS with `s3:GetObject`, `s3:ListBucket` permissions |
| Bastion Host | SSH access from either GitLab Runner or local PC |
| RDS Storage | Must be **≥ 1.5×** the total dump file size |
| S3 Bucket | Pre-created with appropriate bucket policy |

### Option A — Additional Prerequisites

| Requirement | Details |
|---|---|
| GitLab Runner | Runner with network access to bastion host |
| Oracle Client on Bastion | `expdp`, `impdp`, `SQL*Plus` installed on bastion host |
| GitLab CI/CD Variables | `BASTION_KEY`, `RDS_PASSWORD`, `RDS_MASTER_USER` set as masked variables |

### Option B — Additional Prerequisites

| Requirement | Details |
|---|---|
| Oracle Instant Client | Installed locally — version must match RDS Oracle major version |
| SSH Key | Private key for bastion host access on local PC (`~/.ssh/bastion-key.pem`) |
| Local Port 1521 Free | Ensure nothing else is binding port 1521 locally before opening the tunnel |

---

## Step 1 — Export from On-Prem

Run `expdp` on the on-premises Oracle server. This exports the target schema(s) into compressed dump files with parallelism for performance.

```bash
expdp system/password@ONPREM \
  schemas=APP \
  directory=DATA_PUMP_DIR \
  dumpfile=app_%U.dmp \
  logfile=app_export.log \
  parallel=8 \
  compression=all \
  exclude=statistics
```

**Parameter Notes:**

| Parameter | Purpose |
|---|---|
| `schemas=APP` | Schema(s) to export — adjust as needed |
| `dumpfile=app_%U.dmp` | `%U` generates multiple files for parallel export |
| `parallel=8` | Adjust based on server CPU capacity |
| `compression=all` | Reduces dump size — recommended for large schemas |
| `exclude=statistics` | Skips stale stats; re-gathered post-import |

> ⚠️ **Note:** Never embed plaintext passwords in scripts. Use Oracle Wallet or pass credentials via a secure vault at runtime.

---

## Step 2 — Upload to S3

Sync the dump files from the on-prem Data Pump directory to the S3 staging bucket.

```bash
aws s3 sync /dpump/ s3://<bucket>/oracle/prod-cutover/
```

> 💡 **Tip:** Use `--storage-class STANDARD_IA` for large dumps if files will remain in S3 temporarily before import. Verify upload integrity with `--exact-timestamps`.

---

## Step 3 — Download into RDS

> Applies to **both options**. For Option A, these SQL commands run on the bastion via GitLab SSH. For Option B, run them locally — the SSH tunnel routes the connection to RDS transparently.

### 3a. Trigger the S3 Download

Connect to RDS using SQL*Plus as the master user and execute the `rdsadmin` download procedure.

```sql
DECLARE
  l_task_id VARCHAR2(100);
BEGIN
  l_task_id := rdsadmin.rdsadmin_s3_tasks.download_from_s3(
    p_bucket_name    => '<bucket>',
    p_s3_prefix      => 'oracle/prod-cutover/',
    p_directory_name => 'DATA_PUMP_DIR'
  );
  DBMS_OUTPUT.put_line('TASK_ID=' || l_task_id);
END;
/
```

> 📝 Note the `TASK_ID` printed in output — you'll need it to monitor progress below.

---

### 3b. Monitor the Download Task

Poll the task log to confirm completion or diagnose errors.

```sql
SELECT text
FROM TABLE(
  rdsadmin.rds_file_util.read_text_file(
    'BDUMP',
    'dbtask-<TASK_ID>.log'
  )
);
```

---

### 3c. Verify Files in DATA_PUMP_DIR

Confirm all dump files are present before starting the import.

```sql
SELECT *
FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR'));
```

---

## Step 4 — Import into RDS

> Applies to **both options**. For Option A, `impdp` runs on the bastion host via GitLab SSH. For Option B, `impdp` runs locally and connects to RDS via the SSH tunnel on `127.0.0.1:1521`.

Run `impdp` from the bastion host (Option A) or from your local PC (Option B), connecting to the RDS endpoint.

```bash
impdp master_user/password@//rds-endpoint:1521/ORCL \
  directory=DATA_PUMP_DIR \
  dumpfile=app_%U.dmp \
  logfile=app_import.log \
  parallel=8 \
  schemas=APP \
  transform=segment_attributes:n \
  exclude=statistics
```

**Parameter Notes:**

| Parameter | Purpose |
|---|---|
| `transform=segment_attributes:n` | Strips on-prem tablespace/storage attributes — lets RDS use its own defaults |
| `exclude=statistics` | Avoids importing stale optimizer stats |
| `parallel=8` | Match or tune to RDS instance vCPU count |

> ⚠️ **Note:** If the target schema or users do not exist on RDS, pre-create them or add `remap_schema=APP:TARGET_SCHEMA` as needed.

---

## Post-Import Validation

### Check for Invalid Objects

```sql
SELECT owner, object_type, COUNT(*)
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type;
```

### Recompile Invalid Objects

```sql
EXEC UTL_RECOMP.RECOMP_PARALLEL(4);
```

### Gather Fresh Schema Statistics

```sql
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('APP');
```

> 💡 Re-run the invalid objects query after recompilation to confirm all objects compiled successfully.

---

## Cutover Checklist

Use this checklist during the final production cutover.

- [ ] **Freeze writes** — put the application in maintenance mode or stop write traffic to on-prem Oracle
- [ ] **Run final delta export** — re-run `expdp` for any incremental/changed data since the initial export
- [ ] **Upload delta to S3** — sync updated dump files
- [ ] **Import delta into RDS** — run `impdp` for the delta dump
- [ ] **Validate objects and stats** — run post-import validation queries
- [ ] **Update connection strings** — update all application configs, JDBC URLs, and secrets to point to the RDS endpoint
- [ ] **Run smoke tests** — execute critical application workflows against RDS
- [ ] **Monitor** — watch RDS CloudWatch metrics (CPU, IOPS, connections) and application logs for errors

---

## Security Best Practices

| Area | Recommendation |
|---|---|
| Credentials | Use AWS Secrets Manager or CI/CD secret variables — never hardcode passwords |
| Master Password | Rotate the RDS master user password after migration is complete |
| S3 Access | Restrict bucket policy to only the RDS IAM role and migration bastion IAM identity |
| Audit Logging | Enable RDS Oracle audit logs and ship to CloudWatch Logs or S3 |
| Encryption | Ensure S3 bucket uses SSE-S3 or SSE-KMS; enable RDS encryption at rest |
| Network | Confirm RDS security group allows inbound only from bastion host SG on port 1521 |
| Option B — SSH Key | Store bastion private key with `chmod 400`; never share or commit it |
| Option B — Tunnel | Close the SSH tunnel immediately after migration is complete |
| Option B — Local Creds | Use shell `export` for passwords during the session; unset after (`unset RDS_PASSWORD`) |

---

## Outcome

This runbook provides a **repeatable, auditable** Oracle migration process using native AWS tooling (Data Pump + S3 Integration), minimising operational risk and enabling delta/incremental re-runs if needed before final cutover.
