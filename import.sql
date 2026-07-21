SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100

-- ============================================================
-- STEP 1: Download dump file from S3 into DATA_PUMP_DIR
-- ============================================================
COLUMN task_id NEW_VALUE v_task_id NOPRINT
SELECT rdsadmin.rdsadmin_s3_tasks.download_from_s3(
   p_bucket_name    => 'your-bucket-name',
   p_s3_prefix      => 'dvm_dev.dmp',
   p_directory_name => 'DATA_PUMP_DIR')
AS TASK_ID FROM DUAL;

-- ============================================================
-- STEP 2: Check the download task log (uses task_id captured above)
-- ============================================================
SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('BDUMP','dbtask-&v_task_id..log'));

-- ============================================================
-- STEP 3: Confirm the dump file landed in DATA_PUMP_DIR
-- ============================================================
SELECT filename, type, filesize, mtime
FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR'))
ORDER BY mtime;

-- ============================================================
-- STEP 4: Run the Data Pump import job
-- ============================================================
DECLARE
  hdnl NUMBER;
BEGIN
  hdnl := DBMS_DATAPUMP.OPEN(
            operation => 'IMPORT',
            job_mode  => 'SCHEMA',
            job_name  => NULL);

  DBMS_DATAPUMP.ADD_FILE(
    handle    => hdnl,
    filename  => 'dvm_dev.dmp',
    directory => 'DATA_PUMP_DIR',
    filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_DUMP_FILE);

  DBMS_DATAPUMP.ADD_FILE(
    handle    => hdnl,
    filename  => 'dvm_dev_import.log',
    directory => 'DATA_PUMP_DIR',
    filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE);

  DBMS_DATAPUMP.METADATA_FILTER(hdnl, 'SCHEMA_EXPR', 'IN (''DVM_DEV'')');

  -- Uncomment if the schema doesn't already exist in this RDS instance:
  -- DBMS_DATAPUMP.METADATA_REMAP(hdnl, 'REMAP_SCHEMA', 'DVM_DEV', 'DVM_DEV');

  DBMS_DATAPUMP.START_JOB(hdnl);

  DBMS_OUTPUT.PUT_LINE('Data Pump import job started.');
END;
/

-- ============================================================
-- STEP 5: Monitor job progress (re-run until no rows come back)
-- ============================================================
SELECT owner_name, job_name, operation, job_mode, state
FROM dba_datapump_jobs
WHERE state = 'EXECUTING';

-- ============================================================
-- STEP 6: Review the import log once the job completes
-- ============================================================
SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('DATA_PUMP_DIR','dvm_dev_import.log'));

-- ============================================================
-- STEP 7 (OPTIONAL): Clean up the dump file after successful import
-- ============================================================
-- EXEC UTL_FILE.FREMOVE('DATA_PUMP_DIR','dvm_dev.dmp');
