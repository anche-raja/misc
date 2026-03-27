#!/usr/bin/env python3
"""
=============================================================================
Oracle Migration Validation Script — ZERO EXTERNAL DEPENDENCIES
=============================================================================
Uses ONLY Python standard library + sqlplus (Oracle Client already installed)
No pip installs required.

Requirements:
  - Python 3.6+  (standard on all enterprise Linux/Windows)
  - sqlplus      (already installed with Oracle Client)

Usage:
  python migration_validator.py                  # Run all checks
  python migration_validator.py --level 1        # Level 1 only
  python migration_validator.py --level 2        # Level 2 only
  python migration_validator.py --help

Output:
  ./validation_reports/migration_report_<timestamp>.html
  ./validation_reports/migration_report_<timestamp>.csv
  ./validation_reports/migration_report_<timestamp>_diff.csv
=============================================================================
"""

import subprocess
import os
import sys
import csv
import argparse
import re
from datetime import datetime
from html import escape
from io import StringIO

# =============================================================================
# !! CONFIGURE THESE BEFORE RUNNING !!
# =============================================================================
DB_CONFIG = {
    "source": {
        "user":         "system",
        "password":     "your_source_password",
        "host":         "onprem-oracle-host",
        "port":         "1521",
        "service":      "ORCL",
        # OR use EZConnect string directly:
        # "ezconnect": "system/password@onprem-host:1521/ORCL"
    },
    "target": {
        "user":         "admin",
        "password":     "your_target_password",
        "host":         "xxxx.rds.amazonaws.com",
        "port":         "1521",
        "service":      "ORCL",
    }
}

SCHEMA_NAME  = "DVM"
SQLPLUS_BIN  = "sqlplus"          # Full path if not on PATH e.g. /u01/app/oracle/product/19c/bin/sqlplus
REPORT_DIR   = "./validation_reports"
RUN_TS       = datetime.now().strftime("%Y%m%d_%H%M%S")
COL_SEP      = "~|~"              # Unlikely to appear in data

# =============================================================================
# ALL VALIDATION QUERIES
# =============================================================================
QUERIES = {
    # -------------------------------------------------------------------------
    # LEVEL 1 — Object & Role Presence Checks
    # -------------------------------------------------------------------------
    "L1_01_Object_Summary": {
        "level": 1,
        "desc":  "Object count by type — valid vs invalid",
        "sql": f"""
SELECT object_type,
       COUNT(*) AS total_objects,
       SUM(CASE WHEN status='VALID'   THEN 1 ELSE 0 END) AS valid_count,
       SUM(CASE WHEN status='INVALID' THEN 1 ELSE 0 END) AS invalid_count
FROM   dba_objects
WHERE  owner = '{SCHEMA_NAME}'
GROUP  BY object_type
ORDER  BY object_type;"""
    },

    "L1_02_Invalid_Objects": {
        "level": 1,
        "desc":  "INVALID objects — must be ZERO rows on target",
        "sql": f"""
SELECT object_name, object_type, status,
       TO_CHAR(last_ddl_time,'YYYY-MM-DD HH24:MI:SS') AS last_ddl_time
FROM   dba_objects
WHERE  owner  = '{SCHEMA_NAME}'
  AND  status = 'INVALID'
ORDER  BY object_type, object_name;"""
    },

    "L1_03_Tables": {
        "level": 1,
        "desc":  "All tables with status and partitioning",
        "sql": f"""
SELECT table_name, num_rows, status, partitioned, iot_type, compression
FROM   dba_tables
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY table_name;"""
    },

    "L1_04_Indexes": {
        "level": 1,
        "desc":  "All indexes with type and status",
        "sql": f"""
SELECT index_name, table_name, index_type, uniqueness, status, partitioned
FROM   dba_indexes
WHERE  table_owner = '{SCHEMA_NAME}'
ORDER  BY table_name, index_name;"""
    },

    "L1_05_Constraints_Summary": {
        "level": 1,
        "desc":  "Constraint count per table by type",
        "sql": f"""
SELECT table_name, constraint_type,
       COUNT(*) AS constraint_count,
       SUM(CASE WHEN status='ENABLED'  THEN 1 ELSE 0 END) AS enabled_count,
       SUM(CASE WHEN status='DISABLED' THEN 1 ELSE 0 END) AS disabled_count
FROM   dba_constraints
WHERE  owner = '{SCHEMA_NAME}'
  AND  constraint_type IN ('P','U','R','C')
GROUP  BY table_name, constraint_type
ORDER  BY table_name, constraint_type;"""
    },

    "L1_06_Stored_Code": {
        "level": 1,
        "desc":  "Procedures, Functions, Packages, Triggers",
        "sql": f"""
SELECT object_name, object_type, status,
       TO_CHAR(last_ddl_time,'YYYY-MM-DD') AS last_compiled
FROM   dba_objects
WHERE  owner = '{SCHEMA_NAME}'
  AND  object_type IN (
         'PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY',
         'TRIGGER','TYPE','TYPE BODY'
       )
ORDER  BY object_type, object_name;"""
    },

    "L1_07_Views": {
        "level": 1,
        "desc":  "All views with text length",
        "sql": f"""
SELECT view_name, text_length, read_only
FROM   dba_views
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY view_name;"""
    },

    "L1_08_Sequences": {
        "level": 1,
        "desc":  "Sequence definitions",
        "sql": f"""
SELECT sequence_name, min_value, max_value,
       increment_by, cycle_flag, cache_size, last_number
FROM   dba_sequences
WHERE  sequence_owner = '{SCHEMA_NAME}'
ORDER  BY sequence_name;"""
    },

    "L1_09_Synonyms": {
        "level": 1,
        "desc":  "Private and public synonyms",
        "sql": f"""
SELECT 'PRIVATE' AS synonym_type, synonym_name, table_owner, table_name, db_link
FROM   dba_synonyms WHERE owner = '{SCHEMA_NAME}'
UNION ALL
SELECT 'PUBLIC', synonym_name, table_owner, table_name, db_link
FROM   dba_synonyms WHERE owner='PUBLIC' AND table_owner='{SCHEMA_NAME}'
ORDER  BY 1, 2;"""
    },

    "L1_10_DB_Links": {
        "level": 1,
        "desc":  "Database links from DVM schema",
        "sql": f"""
SELECT db_link, username, host,
       TO_CHAR(created,'YYYY-MM-DD') AS created_date
FROM   dba_db_links
WHERE  owner = '{SCHEMA_NAME}';"""
    },

    "L1_11_Users": {
        "level": 1,
        "desc":  "Database user accounts with status",
        "sql": """
SELECT username, account_status, default_tablespace,
       temporary_tablespace, profile,
       TO_CHAR(created,'YYYY-MM-DD') AS created_date
FROM   dba_users
WHERE  username NOT IN (
         'SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','MDSYS','ORDSYS',
         'EXFSYS','DMSYS','WMSYS','CTXSYS','ANONYMOUS','XDB',
         'APPQOSSYS','RDSADMIN','RDSSEC','ORDPLUGINS','OLAPSYS'
       )
ORDER  BY username;"""
    },

    "L1_12_Roles": {
        "level": 1,
        "desc":  "Custom roles defined in DB",
        "sql": """
SELECT role, password_required, authentication_type
FROM   dba_roles
WHERE  role NOT IN (
         'CONNECT','RESOURCE','DBA','SELECT_CATALOG_ROLE',
         'EXECUTE_CATALOG_ROLE','DELETE_CATALOG_ROLE',
         'EXP_FULL_DATABASE','IMP_FULL_DATABASE',
         'DATAPUMP_EXP_FULL_DATABASE','DATAPUMP_IMP_FULL_DATABASE',
         'SCHEDULER_ADMIN','GATHER_SYSTEM_STATISTICS',
         'RECOVERY_CATALOG_OWNER','AQ_USER_ROLE','AQ_ADMINISTRATOR_ROLE',
         'HS_ADMIN_ROLE','XDBADMIN','XDB_SET_INVOKER','XDB_WEBSERVICES'
       )
ORDER  BY role;"""
    },

    "L1_13_Role_Grants": {
        "level": 1,
        "desc":  "Roles granted to DVM user",
        "sql": f"""
SELECT grantee, granted_role, admin_option, default_role
FROM   dba_role_privs
WHERE  grantee = '{SCHEMA_NAME}'
ORDER  BY granted_role;"""
    },

    "L1_14_Sys_Privileges": {
        "level": 1,
        "desc":  "System privileges granted to DVM",
        "sql": f"""
SELECT grantee, privilege, admin_option
FROM   dba_sys_privs
WHERE  grantee = '{SCHEMA_NAME}'
ORDER  BY privilege;"""
    },

    "L1_15_Object_Privileges": {
        "level": 1,
        "desc":  "Object-level grants on DVM objects",
        "sql": f"""
SELECT grantee, owner, table_name, privilege, grantable
FROM   dba_tab_privs
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY table_name, grantee, privilege;"""
    },

    "L1_16_Tablespace_Quotas": {
        "level": 1,
        "desc":  "Tablespace quotas for DVM user",
        "sql": f"""
SELECT username, tablespace_name,
       ROUND(bytes/1024/1024,2) AS used_mb,
       CASE WHEN max_bytes=-1 THEN 'UNLIMITED'
            ELSE TO_CHAR(ROUND(max_bytes/1024/1024,2)) END AS max_mb
FROM   dba_ts_quotas
WHERE  username = '{SCHEMA_NAME}';"""
    },

    "L1_17_Mat_Views": {
        "level": 1,
        "desc":  "Materialized views",
        "sql": f"""
SELECT mview_name, refresh_mode, refresh_method,
       build_mode, staleness, compile_state
FROM   dba_mviews
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY mview_name;"""
    },

    "L1_18_Scheduler_Jobs": {
        "level": 1,
        "desc":  "Scheduler jobs",
        "sql": f"""
SELECT job_name, job_type, state, enabled,
       TO_CHAR(last_start_date,'YYYY-MM-DD HH24:MI:SS') AS last_run,
       TO_CHAR(next_run_date,  'YYYY-MM-DD HH24:MI:SS') AS next_run
FROM   dba_scheduler_jobs
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY job_name;"""
    },

    "L1_19_Grand_Scorecard": {
        "level": 1,
        "desc":  "Grand object count scorecard",
        "sql": f"""
SELECT 'TABLES'              AS category, COUNT(*) AS cnt FROM dba_tables    WHERE owner='{SCHEMA_NAME}'
UNION ALL SELECT 'VIEWS',                 COUNT(*) FROM dba_views      WHERE owner='{SCHEMA_NAME}'
UNION ALL SELECT 'INDEXES',              COUNT(*) FROM dba_indexes     WHERE table_owner='{SCHEMA_NAME}'
UNION ALL SELECT 'PROCEDURES',           COUNT(*) FROM dba_objects     WHERE owner='{SCHEMA_NAME}' AND object_type='PROCEDURE'
UNION ALL SELECT 'FUNCTIONS',            COUNT(*) FROM dba_objects     WHERE owner='{SCHEMA_NAME}' AND object_type='FUNCTION'
UNION ALL SELECT 'PACKAGES',             COUNT(*) FROM dba_objects     WHERE owner='{SCHEMA_NAME}' AND object_type='PACKAGE'
UNION ALL SELECT 'PACKAGE BODIES',       COUNT(*) FROM dba_objects     WHERE owner='{SCHEMA_NAME}' AND object_type='PACKAGE BODY'
UNION ALL SELECT 'TRIGGERS',             COUNT(*) FROM dba_triggers    WHERE owner='{SCHEMA_NAME}'
UNION ALL SELECT 'SEQUENCES',            COUNT(*) FROM dba_sequences   WHERE sequence_owner='{SCHEMA_NAME}'
UNION ALL SELECT 'SYNONYMS',             COUNT(*) FROM dba_synonyms    WHERE owner='{SCHEMA_NAME}'
UNION ALL SELECT 'TYPES',                COUNT(*) FROM dba_objects     WHERE owner='{SCHEMA_NAME}' AND object_type='TYPE'
UNION ALL SELECT 'MAT VIEWS',            COUNT(*) FROM dba_mviews      WHERE owner='{SCHEMA_NAME}'
UNION ALL SELECT 'INVALID OBJECTS',      COUNT(*) FROM dba_objects     WHERE owner='{SCHEMA_NAME}' AND status='INVALID'
UNION ALL SELECT 'DISABLED CONSTRAINTS', COUNT(*) FROM dba_constraints WHERE owner='{SCHEMA_NAME}' AND status='DISABLED'
UNION ALL SELECT 'UNUSABLE INDEXES',     COUNT(*) FROM dba_indexes     WHERE table_owner='{SCHEMA_NAME}' AND status='UNUSABLE'
UNION ALL SELECT 'COMPILE ERRORS',       COUNT(*) FROM dba_errors      WHERE owner='{SCHEMA_NAME}'
ORDER  BY 1;"""
    },

    # -------------------------------------------------------------------------
    # LEVEL 2 — Comprehensive Data Integrity & Count Checks
    # -------------------------------------------------------------------------
    "L2_01_Row_Counts": {
        "level": 2,
        "desc":  "Exact row count per table using dynamic SQL",
        "sql": f"""
SELECT t.table_name,
       TO_NUMBER(
           EXTRACTVALUE(
               XMLTYPE(DBMS_XMLGEN.GETXML(
                   'SELECT COUNT(*) c FROM {SCHEMA_NAME}.' || t.table_name
               )), '//text()'
           )
       ) AS row_count
FROM   dba_tables t
WHERE  t.owner = '{SCHEMA_NAME}'
ORDER  BY t.table_name;"""
    },

    "L2_02_Column_Structure": {
        "level": 2,
        "desc":  "Column-level structure — type, length, nullability",
        "sql": f"""
SELECT table_name, column_id, column_name, data_type,
       data_length, data_precision, data_scale,
       nullable, virtual_column
FROM   dba_tab_columns
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY table_name, column_id;"""
    },

    "L2_03_Column_Count_Per_Table": {
        "level": 2,
        "desc":  "Column count summary per table",
        "sql": f"""
SELECT table_name,
       COUNT(*) AS total_columns,
       SUM(CASE WHEN nullable='N'         THEN 1 ELSE 0 END) AS not_null_cols,
       SUM(CASE WHEN virtual_column='YES' THEN 1 ELSE 0 END) AS virtual_cols,
       SUM(CASE WHEN data_default IS NOT NULL THEN 1 ELSE 0 END) AS default_cols
FROM   dba_tab_columns
WHERE  owner = '{SCHEMA_NAME}'
GROUP  BY table_name
ORDER  BY table_name;"""
    },

    "L2_04_PK_With_Columns": {
        "level": 2,
        "desc":  "Primary key constraints with column list",
        "sql": f"""
SELECT c.table_name, c.constraint_name, c.status, c.validated,
       LISTAGG(cc.column_name,',') WITHIN GROUP (ORDER BY cc.position) AS pk_columns
FROM   dba_constraints  c
JOIN   dba_cons_columns cc ON cc.owner=c.owner AND cc.constraint_name=c.constraint_name
WHERE  c.owner = '{SCHEMA_NAME}' AND c.constraint_type='P'
GROUP  BY c.table_name, c.constraint_name, c.status, c.validated
ORDER  BY c.table_name;"""
    },

    "L2_05_FK_With_Columns": {
        "level": 2,
        "desc":  "Foreign key constraints with parent table references",
        "sql": f"""
SELECT c.table_name, c.constraint_name, c.status,
       c.delete_rule, rc.table_name AS parent_table, c.validated
FROM   dba_constraints c
JOIN   dba_constraints rc ON rc.owner=c.r_owner AND rc.constraint_name=c.r_constraint_name
WHERE  c.owner='{SCHEMA_NAME}' AND c.constraint_type='R'
ORDER  BY c.table_name;"""
    },

    "L2_06_Disabled_Constraints": {
        "level": 2,
        "desc":  "Disabled or not-validated constraints — investigate these",
        "sql": f"""
SELECT table_name, constraint_name, constraint_type, status, validated
FROM   dba_constraints
WHERE  owner = '{SCHEMA_NAME}'
  AND  (status='DISABLED' OR validated='NOT VALIDATED')
ORDER  BY table_name;"""
    },

    "L2_07_Index_With_Columns": {
        "level": 2,
        "desc":  "Index details with indexed column list",
        "sql": f"""
SELECT i.table_name, i.index_name, i.index_type, i.uniqueness,
       i.status, i.visibility,
       LISTAGG(ic.column_name,',') WITHIN GROUP (ORDER BY ic.column_position) AS indexed_cols
FROM   dba_indexes     i
JOIN   dba_ind_columns ic ON ic.index_owner=i.owner AND ic.index_name=i.index_name
WHERE  i.table_owner = '{SCHEMA_NAME}'
GROUP  BY i.table_name, i.index_name, i.index_type, i.uniqueness, i.status, i.visibility
ORDER  BY i.table_name, i.index_name;"""
    },

    "L2_08_Unusable_Indexes": {
        "level": 2,
        "desc":  "Unusable indexes — must be ZERO rows",
        "sql": f"""
SELECT index_name, table_name, index_type, status
FROM   dba_indexes
WHERE  table_owner = '{SCHEMA_NAME}'
  AND  status      = 'UNUSABLE';"""
    },

    "L2_09_Code_Line_Counts": {
        "level": 2,
        "desc":  "Source code line counts per object",
        "sql": f"""
SELECT name AS object_name, type AS object_type, COUNT(*) AS source_lines
FROM   dba_source
WHERE  owner = '{SCHEMA_NAME}'
GROUP  BY name, type
ORDER  BY type, name;"""
    },

    "L2_10_Compilation_Errors": {
        "level": 2,
        "desc":  "Compilation errors — must be ZERO rows",
        "sql": f"""
SELECT name AS object_name, type AS object_type,
       line, position, text AS error_text, attribute
FROM   dba_errors
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY name, line;"""
    },

    "L2_11_Package_Body_Mismatch": {
        "level": 2,
        "desc":  "Package spec without body or body without spec",
        "sql": f"""
SELECT NVL(s.object_name, b.object_name) AS package_name,
       CASE WHEN s.object_type IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS spec_status,
       CASE WHEN b.object_type IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS body_status
FROM   (SELECT object_name, object_type FROM dba_objects WHERE owner='{SCHEMA_NAME}' AND object_type='PACKAGE') s
FULL OUTER JOIN
       (SELECT object_name, object_type FROM dba_objects WHERE owner='{SCHEMA_NAME}' AND object_type='PACKAGE BODY') b
ON     s.object_name = b.object_name
WHERE  s.object_type IS NULL OR b.object_type IS NULL
ORDER  BY 1;"""
    },

    "L2_12_Table_Segments": {
        "level": 2,
        "desc":  "Table segment sizes in MB",
        "sql": f"""
SELECT s.segment_name AS table_name,
       ROUND(s.bytes/1024/1024,3) AS size_mb,
       t.num_rows, t.blocks,
       TO_CHAR(t.last_analyzed,'YYYY-MM-DD') AS last_analyzed
FROM   dba_segments s
JOIN   dba_tables   t ON t.owner=s.owner AND t.table_name=s.segment_name
WHERE  s.owner       = '{SCHEMA_NAME}'
  AND  s.segment_type= 'TABLE'
ORDER  BY s.bytes DESC;"""
    },

    "L2_13_LOB_Columns": {
        "level": 2,
        "desc":  "LOB column definitions (CLOB, BLOB)",
        "sql": f"""
SELECT table_name, column_name, lob_name, chunk, cache, in_row
FROM   dba_lobs
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY table_name, column_name;"""
    },

    "L2_14_Partitions": {
        "level": 2,
        "desc":  "Partition details per table",
        "sql": f"""
SELECT pt.table_name, pt.partitioning_type,
       pt.partition_count, pt.subpartitioning_type
FROM   dba_part_tables pt
WHERE  pt.owner = '{SCHEMA_NAME}'
ORDER  BY pt.table_name;"""
    },

    "L2_15_Object_Dependencies": {
        "level": 2,
        "desc":  "Object dependency map (non-system refs)",
        "sql": f"""
SELECT d.name AS object_name, d.type AS object_type,
       d.referenced_name, d.referenced_type, d.referenced_owner
FROM   dba_dependencies d
WHERE  d.owner = '{SCHEMA_NAME}'
  AND  d.referenced_owner NOT IN ('SYS','SYSTEM','PUBLIC','WMSYS','XDB','MDSYS','CTXSYS')
ORDER  BY d.type, d.name, d.referenced_name;"""
    },

    "L2_16_Broken_Dependencies": {
        "level": 2,
        "desc":  "Broken dependencies — objects referenced but missing",
        "sql": f"""
SELECT DISTINCT d.name AS object_name, d.type,
       d.referenced_name AS missing_object,
       d.referenced_type, d.referenced_owner
FROM   dba_dependencies d
WHERE  d.owner = '{SCHEMA_NAME}'
  AND  d.referenced_owner NOT IN ('SYS','SYSTEM','PUBLIC')
  AND  NOT EXISTS (
         SELECT 1 FROM dba_objects o
         WHERE  o.owner=d.referenced_owner AND o.object_name=d.referenced_name
       )
ORDER  BY d.name;"""
    },

    "L2_17_Statistics_Freshness": {
        "level": 2,
        "desc":  "Table statistics freshness (stale stats = bad query plans)",
        "sql": f"""
SELECT table_name, num_rows, blocks,
       TO_CHAR(last_analyzed,'YYYY-MM-DD HH24:MI:SS') AS last_analyzed,
       stale_stats
FROM   dba_tab_statistics
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY last_analyzed NULLS FIRST;"""
    },

    "L2_18_Triggers_Detail": {
        "level": 2,
        "desc":  "Trigger details with event and status",
        "sql": f"""
SELECT trigger_name, trigger_type, triggering_event,
       table_name, status, action_type
FROM   dba_triggers
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY table_name, trigger_name;"""
    },

    "L2_19_Column_Statistics": {
        "level": 2,
        "desc":  "Column statistics — distinct values, nulls, density",
        "sql": f"""
SELECT table_name, column_name, num_distinct, num_nulls,
       ROUND(density,6) AS density, avg_col_len,
       TO_CHAR(last_analyzed,'YYYY-MM-DD') AS last_analyzed
FROM   dba_tab_col_statistics
WHERE  owner = '{SCHEMA_NAME}'
ORDER  BY table_name, column_name;"""
    },

    "L2_20_Datatype_Distribution": {
        "level": 2,
        "desc":  "Data type distribution across all tables",
        "sql": f"""
SELECT data_type,
       COUNT(*)                   AS column_count,
       COUNT(DISTINCT table_name) AS tables_using_type
FROM   dba_tab_columns
WHERE  owner = '{SCHEMA_NAME}'
GROUP  BY data_type
ORDER  BY column_count DESC;"""
    },
}


# =============================================================================
# SQLPLUS RUNNER
# =============================================================================

def build_connection_string(cfg: dict) -> str:
    """Build sqlplus EZConnect string."""
    return (f"{cfg['user']}/{cfg['password']}"
            f"@{cfg['host']}:{cfg['port']}/{cfg['service']}")


def build_sqlplus_script(sql: str, col_sep: str) -> str:
    """Wrap a query in sqlplus formatting directives for CSV-like output."""
    return f"""
SET PAGESIZE 50000
SET LINESIZE 32767
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
SET COLSEP '{col_sep}'
SET NULL '__NULL__'
SET TERMOUT OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

{sql}

EXIT;
"""


def run_sqlplus(cfg: dict, sql: str) -> tuple:
    """
    Execute SQL via sqlplus subprocess.
    Returns (rows: list[list[str]], error: str|None)
    """
    script    = build_sqlplus_script(sql, COL_SEP)
    conn_str  = build_connection_string(cfg)

    try:
        proc = subprocess.run(
            [SQLPLUS_BIN, "-S", conn_str],
            input=script,
            capture_output=True,
            text=True,
            timeout=300           # 5 min max per query
        )

        stdout = proc.stdout
        stderr = proc.stderr.strip()

        if proc.returncode not in (0, None) and not stdout.strip():
            return [], (stderr or f"sqlplus exited with code {proc.returncode}")

        rows = parse_sqlplus_output(stdout)
        return rows, None

    except FileNotFoundError:
        return [], f"sqlplus not found at '{SQLPLUS_BIN}'. Update SQLPLUS_BIN in config."
    except subprocess.TimeoutExpired:
        return [], "Query timed out after 300 seconds"
    except Exception as e:
        return [], str(e)


def parse_sqlplus_output(raw: str) -> list:
    """
    Parse the COL_SEP delimited sqlplus output into list of lists.
    First row is treated as header.
    """
    lines  = raw.splitlines()
    parsed = []

    for line in lines:
        line = line.strip()
        if not line:
            continue
        # Skip separator lines like ---  ---  ---
        if re.match(r'^[-\s]+$', line):
            continue
        # Skip Oracle banner / connection lines
        if any(x in line for x in ["Connected to", "Oracle Database",
                                    "Copyright", "Oracle Corporation",
                                    "SQL>", "SP2-", "ORA-"]):
            # Capture ORA- errors
            if line.startswith("ORA-") or line.startswith("SP2-"):
                parsed.append([line])
            continue
        cols = [c.strip() for c in line.split(COL_SEP)]
        if cols:
            parsed.append(cols)

    return parsed


# =============================================================================
# COMPARISON ENGINE
# =============================================================================

def rows_to_dict_list(rows: list) -> tuple:
    """Convert [[header...],[row...]] to (headers, [dict, ...])"""
    if not rows:
        return [], []
    headers = rows[0]
    data    = []
    for row in rows[1:]:
        # Pad short rows
        while len(row) < len(headers):
            row.append("")
        data.append(dict(zip(headers, row)))
    return headers, data


def compare_results(src_rows: list, tgt_rows: list) -> dict:
    """
    Returns comparison dict:
      match, src_count, tgt_count, only_in_src, only_in_tgt, headers
    """
    src_hdr, src_data = rows_to_dict_list(src_rows)
    tgt_hdr, tgt_data = rows_to_dict_list(tgt_rows)

    headers = src_hdr or tgt_hdr

    # Convert each row dict to a frozenset of items for set comparison
    def to_set(data):
        return set(frozenset(sorted(d.items())) for d in data)

    src_set = to_set(src_data)
    tgt_set = to_set(tgt_data)

    only_src = [dict(fs) for fs in (src_set - tgt_set)]
    only_tgt = [dict(fs) for fs in (tgt_set - src_set)]

    return {
        "match":       len(only_src) == 0 and len(only_tgt) == 0,
        "src_count":   len(src_data),
        "tgt_count":   len(tgt_data),
        "only_in_src": only_src,
        "only_in_tgt": only_tgt,
        "headers":     headers,
        "src_data":    src_data,
        "tgt_data":    tgt_data,
    }


# =============================================================================
# HTML REPORT GENERATOR  (pure stdlib — no jinja2)
# =============================================================================

def dict_list_to_html_table(headers: list, data: list, max_rows: int = 200) -> str:
    if not data:
        return "<span class='ok-text'>✅ No rows returned</span>"

    display = data[:max_rows]
    th_html = "".join(f"<th>{escape(str(h))}</th>" for h in headers)
    rows_html = ""
    for row in display:
        cells = "".join(f"<td>{escape(str(row.get(h, '')))}</td>" for h in headers)
        rows_html += f"<tr>{cells}</tr>"

    extra = ""
    if len(data) > max_rows:
        extra = (f"<p class='truncated'>Showing {max_rows} of {len(data)} rows. "
                 f"See CSV report for full data.</p>")

    return f"<div class='tbl-wrap'><table class='dt'><thead><tr>{th_html}</tr></thead><tbody>{rows_html}</tbody></table>{extra}</div>"


def generate_html_report(all_results: dict) -> str:
    passed = sum(1 for r in all_results.values() if r["cmp"]["match"])
    failed = sum(1 for r in all_results.values() if not r["cmp"]["match"] and not r.get("error"))
    errors = sum(1 for r in all_results.values() if r.get("error"))
    total  = len(all_results)
    pct    = round((passed / total) * 100, 1) if total else 0

    # Build table rows
    body_rows = ""
    for name, res in all_results.items():
        cmp   = res["cmp"]
        level = res["level"]
        desc  = res["desc"]

        if res.get("error"):
            badge = f"<span class='badge err'>⚠ ERROR</span>"
            row_cls = "row-err"
        elif cmp["match"]:
            badge = f"<span class='badge ok'>✅ MATCH</span>"
            row_cls = "row-ok"
        else:
            badge = f"<span class='badge fail'>❌ MISMATCH</span>"
            row_cls = "row-fail"

        diff_section = ""
        if not cmp["match"] and not res.get("error"):
            if cmp["only_in_src"]:
                diff_section += "<p class='diff-hdr'>⬅ Only in SOURCE (missing from Target):</p>"
                diff_section += dict_list_to_html_table(cmp["headers"], cmp["only_in_src"])
            if cmp["only_in_tgt"]:
                diff_section += "<p class='diff-hdr'>➡ Only in TARGET (extra / unexpected):</p>"
                diff_section += dict_list_to_html_table(cmp["headers"], cmp["only_in_tgt"])

        src_tbl = dict_list_to_html_table(cmp["headers"], cmp["src_data"])
        tgt_tbl = dict_list_to_html_table(cmp["headers"], cmp["tgt_data"])

        err_msg = f"<p class='err-msg'>{escape(res.get('err_msg', ''))}</p>" if res.get("error") else ""

        body_rows += f"""
<tr class='{row_cls}'>
  <td><span class='lvl l{level}'>L{level}</span></td>
  <td>
    <b>{escape(name)}</b><br>
    <small class='desc'>{escape(desc)}</small>
  </td>
  <td>{badge}</td>
  <td class='num'>{cmp['src_count']}</td>
  <td class='num'>{cmp['tgt_count']}</td>
  <td>
    <details>
      <summary>🔍 View Details</summary>
      <div class='det'>
        {err_msg}
        <b>Source Data:</b>{src_tbl}
        <b>Target Data:</b>{tgt_tbl}
        {diff_section}
      </div>
    </details>
  </td>
</tr>"""

    # Progress bar color
    bar_color = "#2e7d32" if pct >= 90 else ("#f57c00" if pct >= 70 else "#c62828")

    html = f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Oracle Migration Validation — {RUN_TS}</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:'Segoe UI',Arial,sans-serif;background:#f0f2f5;color:#222;font-size:14px}}
.hdr{{background:linear-gradient(135deg,#0d1b6e,#1a3a8f);color:#fff;padding:28px 40px}}
.hdr h1{{font-size:1.6rem;margin-bottom:6px}}
.hdr .meta{{opacity:.75;font-size:.9rem;line-height:1.8}}
.summary{{display:flex;flex-wrap:wrap;gap:16px;padding:20px 40px;background:#fff;
          border-bottom:1px solid #dde1e7}}
.card{{background:#f8f9fc;border-radius:8px;padding:14px 22px;min-width:130px;
       text-align:center;border-top:4px solid #ccc}}
.card.c-ok{{border-color:#2e7d32}}.card.c-fail{{border-color:#c62828}}
.card.c-err{{border-color:#e65100}}.card.c-all{{border-color:#1565c0}}
.card .n{{font-size:2rem;font-weight:700;line-height:1.1}}
.card .l{{font-size:.7rem;text-transform:uppercase;letter-spacing:.8px;color:#666;margin-top:4px}}
.prog-wrap{{flex:1;min-width:200px;padding:14px 22px;background:#f8f9fc;
            border-radius:8px;border-top:4px solid {bar_color}}}
.prog-wrap .n{{font-size:2rem;font-weight:700;color:{bar_color}}}
.prog{{height:8px;background:#e0e0e0;border-radius:4px;overflow:hidden;margin-top:8px}}
.prog-bar{{height:100%;border-radius:4px;background:{bar_color};width:{pct}%}}
.content{{padding:24px 40px}}
.main-tbl{{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;
           overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,.1)}}
.main-tbl th{{background:#1a3a8f;color:#fff;padding:11px 14px;text-align:left;
              font-size:.8rem;text-transform:uppercase;letter-spacing:.5px}}
.main-tbl td{{padding:10px 14px;border-bottom:1px solid #eef0f4;vertical-align:top}}
.row-ok{{background:#fafffe}}.row-fail{{background:#fff9f9}}.row-err{{background:#fffaf5}}
.badge{{display:inline-block;padding:3px 10px;border-radius:10px;font-size:.78rem;font-weight:700}}
.badge.ok{{background:#e8f5e9;color:#2e7d32}}.badge.fail{{background:#ffebee;color:#c62828}}
.badge.err{{background:#fff3e0;color:#e65100}}
.lvl{{display:inline-block;padding:2px 7px;border-radius:4px;font-size:.72rem;font-weight:700}}
.l1{{background:#e3f2fd;color:#1565c0}}.l2{{background:#f3e5f5;color:#6a1b9a}}
.num{{text-align:right;font-family:monospace;font-size:.85rem}}
.desc{{color:#666;font-size:.8rem}}
details summary{{cursor:pointer;color:#1565c0;font-size:.82rem;padding:4px 0}}
details summary:hover{{text-decoration:underline}}
.det{{background:#f5f7fa;padding:12px;border-radius:6px;margin-top:8px;overflow:auto}}
.det b{{display:block;margin:8px 0 4px;font-size:.82rem;color:#333}}
.tbl-wrap{{overflow-x:auto;margin-bottom:8px}}
table.dt{{border-collapse:collapse;font-size:.78rem;min-width:400px}}
table.dt th{{background:#455a64;color:#fff;padding:5px 10px;white-space:nowrap}}
table.dt td{{padding:3px 10px;border-bottom:1px solid #e8eaf0;white-space:nowrap}}
table.dt tr:hover td{{background:#f0f4ff}}
.ok-text{{color:#2e7d32;font-style:italic;font-size:.82rem}}
.truncated{{color:#888;font-size:.78rem;font-style:italic;margin-top:4px}}
.diff-hdr{{font-weight:bold;color:#c62828;margin:10px 0 4px;font-size:.82rem}}
.err-msg{{color:#c62828;font-size:.82rem;margin-bottom:8px}}
.footer{{text-align:center;padding:20px;color:#aaa;font-size:.78rem}}
</style>
</head>
<body>

<div class="hdr">
  <h1>🔍 Oracle Migration Validation Report</h1>
  <div class="meta">
    Schema: <b>{SCHEMA_NAME}</b> &nbsp;|&nbsp;
    Source: <b>{DB_CONFIG['source']['host']}</b> &nbsp;|&nbsp;
    Target: <b>{DB_CONFIG['target']['host']}</b> &nbsp;|&nbsp;
    Generated: <b>{RUN_TS}</b>
  </div>
</div>

<div class="summary">
  <div class="card c-all"><div class="n">{total}</div><div class="l">Total Checks</div></div>
  <div class="card c-ok"><div class="n" style="color:#2e7d32">{passed}</div><div class="l">Passed</div></div>
  <div class="card c-fail"><div class="n" style="color:#c62828">{failed}</div><div class="l">Failed</div></div>
  <div class="card c-err"><div class="n" style="color:#e65100">{errors}</div><div class="l">Errors</div></div>
  <div class="prog-wrap">
    <div class="n">{pct}%</div>
    <div class="l">Pass Rate</div>
    <div class="prog"><div class="prog-bar"></div></div>
  </div>
</div>

<div class="content">
  <table class="main-tbl">
    <thead>
      <tr>
        <th style="width:50px">Level</th>
        <th>Check Name</th>
        <th style="width:130px">Status</th>
        <th style="width:80px">Src Rows</th>
        <th style="width:80px">Tgt Rows</th>
        <th>Details</th>
      </tr>
    </thead>
    <tbody>
      {body_rows}
    </tbody>
  </table>
</div>

<div class="footer">
  Oracle Migration Validator &nbsp;|&nbsp; Zero-dependency pure Python &nbsp;|&nbsp; {RUN_TS}
</div>
</body></html>"""

    return html


# =============================================================================
# CSV EXPORT  (stdlib csv module only)
# =============================================================================

def export_summary_csv(all_results: dict, filepath: str):
    with open(filepath, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Check", "Level", "Description", "Status",
                    "Src_Rows", "Tgt_Rows", "Only_In_Src", "Only_In_Tgt"])
        for name, res in all_results.items():
            cmp = res["cmp"]
            status = ("ERROR"    if res.get("error")   else
                      "MATCH"    if cmp["match"]        else "MISMATCH")
            w.writerow([
                name, res["level"], res["desc"], status,
                cmp["src_count"], cmp["tgt_count"],
                len(cmp["only_in_src"]), len(cmp["only_in_tgt"])
            ])
    print(f"  📄 Summary CSV  : {filepath}")


def export_diff_csv(all_results: dict, filepath: str):
    with open(filepath, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Check", "Diff_Side", "Column", "Value"])
        for name, res in all_results.items():
            cmp = res["cmp"]
            if not cmp["match"] and not res.get("error"):
                for row in cmp["only_in_src"]:
                    for col, val in row.items():
                        w.writerow([name, "SOURCE_ONLY", col, val])
                for row in cmp["only_in_tgt"]:
                    for col, val in row.items():
                        w.writerow([name, "TARGET_ONLY", col, val])
    print(f"  📄 Diff CSV     : {filepath}")


# =============================================================================
# MAIN
# =============================================================================

def run_validation(level: int = 0):

    print("=" * 68)
    print(f"  Oracle Migration Validator  |  Schema : {SCHEMA_NAME}")
    print(f"  Source : {DB_CONFIG['source']['host']}:{DB_CONFIG['source']['port']}/{DB_CONFIG['source']['service']}")
    print(f"  Target : {DB_CONFIG['target']['host']}:{DB_CONFIG['target']['port']}/{DB_CONFIG['target']['service']}")
    print(f"  sqlplus: {SQLPLUS_BIN}")
    print("=" * 68)

    # Filter by level
    selected = {
        k: v for k, v in QUERIES.items()
        if level == 0 or v["level"] == level
    }

    print(f"\n  Running {len(selected)} checks (Level {'1+2' if level == 0 else level})...\n")

    all_results = {}

    for check_name, qry in selected.items():
        label = f"[L{qry['level']}] {check_name}"
        sys.stdout.write(f"  {label:<55}")
        sys.stdout.flush()

        src_rows, src_err = run_sqlplus(DB_CONFIG["source"], qry["sql"])
        tgt_rows, tgt_err = run_sqlplus(DB_CONFIG["target"], qry["sql"])

        has_error = bool(src_err or tgt_err)
        err_msg   = " | ".join(filter(None, [src_err, tgt_err]))

        cmp = compare_results(src_rows, tgt_rows)

        all_results[check_name] = {
            "level":   qry["level"],
            "desc":    qry["desc"],
            "cmp":     cmp,
            "error":   has_error,
            "err_msg": err_msg,
        }

        if has_error:
            print(f"⚠  ERROR  — {err_msg}")
        elif cmp["match"]:
            print(f"✅ MATCH  ({cmp['src_count']} rows)")
        else:
            print(f"❌ MISMATCH  "
                  f"src={cmp['src_count']} tgt={cmp['tgt_count']}  "
                  f"diff_src={len(cmp['only_in_src'])} diff_tgt={len(cmp['only_in_tgt'])}")

    # Save reports
    os.makedirs(REPORT_DIR, exist_ok=True)
    html_path    = f"{REPORT_DIR}/migration_report_{RUN_TS}.html"
    summary_csv  = f"{REPORT_DIR}/migration_summary_{RUN_TS}.csv"
    diff_csv     = f"{REPORT_DIR}/migration_diff_{RUN_TS}.csv"

    print(f"\n  Saving reports...")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(generate_html_report(all_results))
    print(f"  🌐 HTML Report  : {html_path}")

    export_summary_csv(all_results, summary_csv)
    export_diff_csv(all_results, diff_csv)

    # Final summary
    passed = sum(1 for r in all_results.values() if r["cmp"]["match"])
    failed = sum(1 for r in all_results.values() if not r["cmp"]["match"] and not r.get("error"))
    errors = sum(1 for r in all_results.values() if r.get("error"))
    total  = len(all_results)
    pct    = round((passed / total) * 100, 1) if total else 0

    print(f"""
  ╔══════════════════════════════════════════╗
  ║         VALIDATION SUMMARY               ║
  ╠══════════════════════════════════════════╣
  ║  Total Checks  : {str(total):<25}║
  ║  ✅ Passed     : {str(passed):<25}║
  ║  ❌ Failed     : {str(failed):<25}║
  ║  ⚠  Errors     : {str(errors):<25}║
  ║  Pass Rate     : {str(pct) + '%':<25}║
  ╚══════════════════════════════════════════╝
    """)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Oracle Migration Validator — Zero external dependencies"
    )
    parser.add_argument(
        "--level", type=int, choices=[0, 1, 2], default=0,
        help="0=All checks (default), 1=Level1 only, 2=Level2 only"
    )
    args = parser.parse_args()
    run_validation(level=args.level)
