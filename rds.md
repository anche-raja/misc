# Oracle On-Prem → Amazon RDS Oracle Migration Runbook

> **Purpose:** Step-by-step procedure to migrate Oracle schemas and data from on-premises Oracle to Amazon RDS for Oracle using Data Pump and S3 Integration.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Step 1 — Export from On-Prem](#step-1--export-from-on-prem)
4. [Step 2 — Upload to S3](#step-2--upload-to-s3)
5. [Step 3 — Download into RDS](#step-3--download-into-rds)
6. [Step 4 — Import into RDS](#step-4--import-into-rds)
7. [Post-Import Validation](#post-import-validation)
8. [Cutover Checklist](#cutover-checklist)
9. [Security Best Practices](#security-best-practices)

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

### CI/CD & Bastion Flow

```
GitLab CI/CD Pipeline
     │
     │  SSH
     ▼
Bastion Host
     ├──► SQL*Plus → RDS (runs download_from_s3 procedure)
     └──► impdp     → RDS (imports from DATA_PUMP_DIR)
```

**Legend:**
- `expdp` export is executed on-prem, typically during downtime window.
- Dump files are uploaded to an Amazon S3 staging prefix.
- GitLab CI/CD connects to the bastion host via SSH to execute SQL*Plus and `impdp` steps.
- RDS downloads dump files from S3 into `DATA_PUMP_DIR` using the `rdsadmin` stored procedure.
- The bastion host runs `impdp` to import dumps from `DATA_PUMP_DIR` into RDS.

---

## Prerequisites

| Requirement | Details |
|---|---|
| RDS Oracle instance | Must have `S3_INTEGRATION` option enabled |
| IAM Role | Attached to RDS with `s3:GetObject`, `s3:ListBucket` permissions |
| Bastion Host | SSH access to reach RDS endpoint and run Oracle client tools |
| RDS Storage | Must be **≥ 1.5×** the total dump file size |
| Oracle Client Tools | `expdp`, `impdp`, `SQL*Plus` installed on bastion |
| S3 Bucket | Pre-created with appropriate bucket policy |

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

Run `impdp` from the bastion host, connecting to the RDS endpoint.

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

---

## Outcome

This runbook provides a **repeatable, auditable** Oracle migration process using native AWS tooling (Data Pump + S3 Integration), minimising operational risk and enabling delta/incremental re-runs if needed before final cutover.
