-- =============================================================================
-- LEVEL 1: INITIAL MIGRATION VALIDATION SCRIPT
-- Purpose : Verify all Objects, Roles, Users, Privileges are moved from
--           On-Prem Oracle to AWS RDS Oracle (DVM Schema)
-- Run on  : BOTH Source (On-Prem) and Target (AWS RDS) and compare output
-- Author  : Migration Validation Team
-- Usage   : sqlplus system/<pwd>@<dsn> @level1_initial_validation.sql
-- =============================================================================

SET LINESIZE 220
SET PAGESIZE 200
SET COLSEP ' | '
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON

DEFINE SCHEMA_NAME = 'DVM'

SPOOL level1_validation_output.txt

PROMPT ============================================================
PROMPT  LEVEL 1 - INITIAL MIGRATION VALIDATION REPORT
PROMPT  Schema  : &SCHEMA_NAME
PROMPT  Run At  : 
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS run_time FROM dual;
PROMPT ============================================================


-- =============================================================================
-- SECTION 1: OBJECT SUMMARY BY TYPE
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [1] OBJECT SUMMARY BY TYPE
PROMPT ------------------------------------------------------------

SELECT
    object_type,
    COUNT(*)                                                      AS total_objects,
    SUM(CASE WHEN status = 'VALID'   THEN 1 ELSE 0 END)          AS valid_count,
    SUM(CASE WHEN status = 'INVALID' THEN 1 ELSE 0 END)          AS invalid_count,
    SUM(CASE WHEN status NOT IN ('VALID','INVALID') THEN 1 ELSE 0 END) AS other_count
FROM dba_objects
WHERE owner = '&SCHEMA_NAME'
GROUP BY object_type
ORDER BY object_type;


-- =============================================================================
-- SECTION 2: INVALID OBJECTS (Must be ZERO on Target)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [2] INVALID OBJECTS  -- Expected: NO ROWS
PROMPT ------------------------------------------------------------

SELECT
    object_name,
    object_type,
    status,
    last_ddl_time
FROM dba_objects
WHERE owner  = '&SCHEMA_NAME'
  AND status = 'INVALID'
ORDER BY object_type, object_name;


-- =============================================================================
-- SECTION 3: TABLES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [3] TABLE LIST WITH STATUS
PROMPT ------------------------------------------------------------

SELECT
    table_name,
    num_rows,
    status,
    partitioned,
    iot_type,
    compression,
    row_movement
FROM dba_tables
WHERE owner = '&SCHEMA_NAME'
ORDER BY table_name;


-- =============================================================================
-- SECTION 4: INDEXES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [4] INDEX LIST
PROMPT ------------------------------------------------------------

SELECT
    index_name,
    table_name,
    index_type,
    uniqueness,
    status,
    partitioned,
    funcidx_status
FROM dba_indexes
WHERE table_owner = '&SCHEMA_NAME'
ORDER BY table_name, index_name;


-- =============================================================================
-- SECTION 5: CONSTRAINTS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [5] CONSTRAINTS SUMMARY PER TABLE
PROMPT ------------------------------------------------------------

SELECT
    table_name,
    constraint_type,
    COUNT(*) AS constraint_count,
    SUM(CASE WHEN status   = 'ENABLED'  THEN 1 ELSE 0 END) AS enabled_count,
    SUM(CASE WHEN status   = 'DISABLED' THEN 1 ELSE 0 END) AS disabled_count,
    SUM(CASE WHEN validated = 'VALIDATED' THEN 1 ELSE 0 END) AS validated_count
FROM dba_constraints
WHERE owner = '&SCHEMA_NAME'
  AND constraint_type IN ('P','U','R','C')
GROUP BY table_name, constraint_type
ORDER BY table_name, constraint_type;


-- =============================================================================
-- SECTION 6: STORED CODE OBJECTS (Procedures, Functions, Packages, Triggers)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [6] STORED CODE OBJECTS
PROMPT ------------------------------------------------------------

SELECT
    object_name,
    object_type,
    status,
    TO_CHAR(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') AS last_compiled
FROM dba_objects
WHERE owner = '&SCHEMA_NAME'
  AND object_type IN (
        'PROCEDURE','FUNCTION',
        'PACKAGE','PACKAGE BODY',
        'TRIGGER',
        'TYPE','TYPE BODY',
        'JAVA CLASS','JAVA SOURCE'
      )
ORDER BY object_type, object_name;


-- =============================================================================
-- SECTION 7: VIEWS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [7] VIEWS
PROMPT ------------------------------------------------------------

SELECT
    view_name,
    text_length,
    read_only
FROM dba_views
WHERE owner = '&SCHEMA_NAME'
ORDER BY view_name;


-- =============================================================================
-- SECTION 8: SEQUENCES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [8] SEQUENCES
PROMPT ------------------------------------------------------------

SELECT
    sequence_name,
    min_value,
    max_value,
    increment_by,
    cycle_flag,
    order_flag,
    cache_size,
    last_number
FROM dba_sequences
WHERE sequence_owner = '&SCHEMA_NAME'
ORDER BY sequence_name;


-- =============================================================================
-- SECTION 9: SYNONYMS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [9] SYNONYMS (Private + Public pointing to DVM)
PROMPT ------------------------------------------------------------

-- Private synonyms owned by DVM
SELECT
    'PRIVATE'    AS synonym_type,
    synonym_name,
    table_owner,
    table_name,
    db_link
FROM dba_synonyms
WHERE owner = '&SCHEMA_NAME'
UNION ALL
-- Public synonyms pointing to DVM objects
SELECT
    'PUBLIC'     AS synonym_type,
    synonym_name,
    table_owner,
    table_name,
    db_link
FROM dba_synonyms
WHERE owner       = 'PUBLIC'
  AND table_owner = '&SCHEMA_NAME'
ORDER BY synonym_type, synonym_name;


-- =============================================================================
-- SECTION 10: DATABASE LINKS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [10] DATABASE LINKS
PROMPT ------------------------------------------------------------

SELECT
    db_link,
    username,
    host,
    TO_CHAR(created,'YYYY-MM-DD') AS created_date
FROM dba_db_links
WHERE owner = '&SCHEMA_NAME';


-- =============================================================================
-- SECTION 11: MATERIALIZED VIEWS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [11] MATERIALIZED VIEWS
PROMPT ------------------------------------------------------------

SELECT
    mview_name,
    refresh_mode,
    refresh_method,
    build_mode,
    last_refresh_type,
    TO_CHAR(last_refresh_date,'YYYY-MM-DD HH24:MI:SS') AS last_refresh_date,
    staleness
FROM dba_mviews
WHERE owner = '&SCHEMA_NAME'
ORDER BY mview_name;


-- =============================================================================
-- SECTION 12: USERS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [12] DATABASE USERS
PROMPT ------------------------------------------------------------

SELECT
    username,
    account_status,
    lock_date,
    expiry_date,
    default_tablespace,
    temporary_tablespace,
    profile,
    TO_CHAR(created,'YYYY-MM-DD') AS created_date
FROM dba_users
WHERE username NOT IN (
    -- Exclude standard Oracle system accounts
    'SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','MDSYS','ORDSYS',
    'EXFSYS','DMSYS','WMSYS','CTXSYS','ANONYMOUS','XDB','ORDPLUGINS',
    'OLAPSYS','FLOWS_030000','FLOWS_FILES','APEX_030200','APEX_040000',
    'OWBSYS','OWBSYS_AUDIT','APPQOSSYS','RDSADMIN','RDSSEC'
)
ORDER BY username;


-- =============================================================================
-- SECTION 13: ROLES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [13] CUSTOM ROLES DEFINED
PROMPT ------------------------------------------------------------

SELECT
    role,
    password_required,
    authentication_type
FROM dba_roles
WHERE role NOT IN (
    -- Exclude built-in Oracle roles
    'CONNECT','RESOURCE','DBA','SELECT_CATALOG_ROLE','EXECUTE_CATALOG_ROLE',
    'DELETE_CATALOG_ROLE','EXP_FULL_DATABASE','IMP_FULL_DATABASE',
    'RECOVERY_CATALOG_OWNER','SCHEDULER_ADMIN','HS_ADMIN_ROLE',
    'GATHER_SYSTEM_STATISTICS','LOGSTDBY_ADMINISTRATOR','AQ_USER_ROLE',
    'AQ_ADMINISTRATOR_ROLE','OLAP_XS_ADMIN','OLAP_DBA','OLAP_USER',
    'AUDIT_ADMIN','AUDIT_VIEWER','CAPTURE_ADMIN','DATAPUMP_EXP_FULL_DATABASE',
    'DATAPUMP_IMP_FULL_DATABASE','ADM_PARALLEL_EXECUTE_TASK',
    'XDBADMIN','XDB_SET_INVOKER','XDB_WEBSERVICES',
    'XDB_WEBSERVICES_OVER_HTTP','XDB_WEBSERVICES_WITH_PUBLIC'
)
ORDER BY role;


-- =============================================================================
-- SECTION 14: ROLE GRANTS TO USERS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [14] ROLE GRANTS TO SCHEMA USER (DVM)
PROMPT ------------------------------------------------------------

SELECT
    grantee,
    granted_role,
    admin_option,
    default_role
FROM dba_role_privs
WHERE grantee = '&SCHEMA_NAME'
ORDER BY granted_role;


-- =============================================================================
-- SECTION 15: SYSTEM PRIVILEGES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [15] SYSTEM PRIVILEGES GRANTED TO DVM
PROMPT ------------------------------------------------------------

SELECT
    grantee,
    privilege,
    admin_option
FROM dba_sys_privs
WHERE grantee = '&SCHEMA_NAME'
ORDER BY privilege;


-- =============================================================================
-- SECTION 16: OBJECT PRIVILEGES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [16] OBJECT LEVEL PRIVILEGES (Granted ON DVM objects)
PROMPT ------------------------------------------------------------

SELECT
    grantee,
    owner,
    table_name,
    privilege,
    grantable,
    hierarchy
FROM dba_tab_privs
WHERE owner = '&SCHEMA_NAME'
ORDER BY table_name, grantee, privilege;


-- =============================================================================
-- SECTION 17: TABLESPACE QUOTAS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [17] TABLESPACE QUOTAS FOR DVM USER
PROMPT ------------------------------------------------------------

SELECT
    username,
    tablespace_name,
    ROUND(bytes/1024/1024,2)       AS used_mb,
    CASE WHEN max_bytes = -1
         THEN 'UNLIMITED'
         ELSE TO_CHAR(ROUND(max_bytes/1024/1024,2))
    END                            AS max_mb
FROM dba_ts_quotas
WHERE username = '&SCHEMA_NAME';


-- =============================================================================
-- SECTION 18: TRIGGERS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [18] TRIGGERS
PROMPT ------------------------------------------------------------

SELECT
    trigger_name,
    trigger_type,
    triggering_event,
    table_name,
    status
FROM dba_triggers
WHERE owner = '&SCHEMA_NAME'
ORDER BY table_name, trigger_name;


-- =============================================================================
-- SECTION 19: SCHEDULER JOBS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [19] SCHEDULER JOBS
PROMPT ------------------------------------------------------------

SELECT
    job_name,
    job_type,
    job_action,
    state,
    enabled,
    last_start_date,
    next_run_date
FROM dba_scheduler_jobs
WHERE owner = '&SCHEMA_NAME'
ORDER BY job_name;


-- =============================================================================
-- SECTION 20: GRAND TOTAL SUMMARY
-- =============================================================================
PROMPT
PROMPT ============================================================
PROMPT  [20] GRAND SUMMARY - OBJECT COUNT BY TYPE
PROMPT ============================================================

SELECT
    NVL(object_type,'** TOTAL **') AS object_type,
    COUNT(*)                       AS total_count
FROM dba_objects
WHERE owner = '&SCHEMA_NAME'
GROUP BY ROLLUP(object_type)
ORDER BY object_type NULLS LAST;

PROMPT
PROMPT ============================================================
PROMPT  END OF LEVEL 1 VALIDATION REPORT
PROMPT ============================================================

SPOOL OFF
