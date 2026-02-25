
# Oracle On-Prem → Amazon RDS Oracle Migration  
## Using Data Pump + S3 Integration (`rdsadmin.rdsadmin_s3_tasks`)

This repository documents the standard migration approach for moving an Oracle schema and data from an on-premises database to Amazon RDS for Oracle.

---

## Architecture Overview

On-Prem Oracle → expdp → S3 → download_from_s3 → RDS DATA_PUMP_DIR → impdp → RDS

---

## Prerequisites

### RDS Configuration
Enable S3_INTEGRATION option group.

### IAM Role
Allow:
- s3:GetObject
- s3:ListBucket

### S3 Structure
s3://my-migration-bucket/oracle/prod-cutover/

---

## Step 1 — Export

expdp system/password@ONPREM \
  schemas=APP \
  directory=DATA_PUMP_DIR \
  dumpfile=app_%U.dmp \
  logfile=app_export.log \
  parallel=8 \
  compression=all \
  exclude=statistics

---

## Step 2 — Upload

aws s3 sync /dpump/ s3://my-migration-bucket/oracle/prod-cutover/

---

## Step 3 — Download to RDS

SELECT rdsadmin.rdsadmin_s3_tasks.download_from_s3(
  p_bucket_name    => 'my-migration-bucket',
  p_s3_prefix      => 'oracle/prod-cutover/',
  p_directory_name => 'DATA_PUMP_DIR'
) AS task_id
FROM dual;

---

## Step 4 — Monitor

SELECT text
FROM TABLE(
  rdsadmin.rds_file_util.read_text_file(
    'BDUMP',
    'dbtask-<TASK_ID>.log'
  )
);

---

## Step 5 — Verify

SELECT *
FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR'));

---

## Step 6 — Import

impdp master_user/password@//rds-endpoint:1521/ORCL \
  directory=DATA_PUMP_DIR \
  dumpfile=app_%U.dmp \
  logfile=app_import.log \
  parallel=8 \
  schemas=APP \
  transform=segment_attributes:n \
  exclude=statistics

---

## Validation

SELECT owner, object_type, COUNT(*)
FROM dba_objects
WHERE status='INVALID'
GROUP BY owner, object_type;

EXEC UTL_RECOMP.RECOMP_PARALLEL(4);
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('APP');

---

## Outcome

✔ Repeatable migration  
✔ Automated pipeline support  
✔ Production-ready approach  
