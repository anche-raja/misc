-- =============================================================================
-- LEVEL 2: COMPREHENSIVE DATA INTEGRITY & COUNT VALIDATION SCRIPT
-- Purpose : Deep validation of data integrity, row counts, DDL structures,
--           constraint health, index status, storage, and code validity
-- Run on  : BOTH Source (On-Prem) and Target (AWS RDS) and compare output
-- Author  : Migration Validation Team
-- Usage   : sqlplus system/<pwd>@<dsn> @level2_comprehensive_validation.sql
-- =============================================================================

SET LINESIZE 250
SET PAGESIZE 500
SET COLSEP ' | '
SET LONG 50000
SET LONGCHUNKSIZE 50000
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED

DEFINE SCHEMA_NAME = 'DVM'

SPOOL level2_comprehensive_output.txt

PROMPT ============================================================
PROMPT  LEVEL 2 - COMPREHENSIVE DATA INTEGRITY VALIDATION REPORT
PROMPT  Schema  : &SCHEMA_NAME
PROMPT  Run At  :
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS run_time FROM dual;
PROMPT ============================================================


-- =============================================================================
-- SECTION 1: EXACT ROW COUNTS FOR EVERY TABLE
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [1] EXACT ROW COUNTS - ALL TABLES (Dynamic Execution)
PROMPT  Compare these counts between Source and Target exactly
PROMPT ------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
    v_count   NUMBER;
    v_sql     VARCHAR2(500);
BEGIN
    DBMS_OUTPUT.PUT_LINE(
        RPAD('TABLE_NAME', 40) || ' | ' ||
        LPAD('ROW_COUNT', 15)
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));

    FOR rec IN (
        SELECT table_name
        FROM   dba_tables
        WHERE  owner = '&SCHEMA_NAME'
        ORDER  BY table_name
    ) LOOP
        v_sql := 'SELECT COUNT(*) FROM &SCHEMA_NAME.' || rec.table_name;
        BEGIN
            EXECUTE IMMEDIATE v_sql INTO v_count;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.table_name, 40) || ' | ' ||
                LPAD(TO_CHAR(v_count, '999,999,999,999'), 15)
            );
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(rec.table_name, 40) || ' | ERROR: ' || SQLERRM
                );
        END;
    END LOOP;
END;
/


-- =============================================================================
-- SECTION 2: TABLE STORAGE & SEGMENT DETAILS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [2] TABLE STORAGE & SEGMENT SIZE
PROMPT ------------------------------------------------------------

SELECT
    s.segment_name                           AS table_name,
    s.segment_type,
    t.num_rows                               AS stats_row_count,
    t.blocks                                 AS stats_blocks,
    ROUND(s.bytes / 1024 / 1024, 3)         AS segment_size_mb,
    t.avg_row_len,
    t.compression,
    t.compress_for,
    TO_CHAR(t.last_analyzed,'YYYY-MM-DD HH24:MI:SS') AS last_analyzed
FROM dba_segments s
JOIN dba_tables   t
    ON  t.owner      = s.owner
    AND t.table_name = s.segment_name
WHERE s.owner        = '&SCHEMA_NAME'
  AND s.segment_type = 'TABLE'
ORDER BY s.bytes DESC;


-- =============================================================================
-- SECTION 3: COLUMN-LEVEL VALIDATION (Structure Check)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [3] COLUMN STRUCTURE PER TABLE
PROMPT  (Compare column names, data types, lengths, nullability)
PROMPT ------------------------------------------------------------

SELECT
    c.table_name,
    c.column_id,
    c.column_name,
    c.data_type,
    c.data_length,
    c.data_precision,
    c.data_scale,
    c.nullable,
    c.data_default,
    c.char_used,
    c.virtual_column
FROM dba_tab_columns c
WHERE c.owner = '&SCHEMA_NAME'
ORDER BY c.table_name, c.column_id;


-- =============================================================================
-- SECTION 4: COLUMN COUNT SUMMARY PER TABLE
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [4] COLUMN COUNT SUMMARY PER TABLE
PROMPT ------------------------------------------------------------

SELECT
    table_name,
    COUNT(*)                                                    AS total_columns,
    SUM(CASE WHEN nullable = 'N' THEN 1 ELSE 0 END)           AS not_null_columns,
    SUM(CASE WHEN nullable = 'Y' THEN 1 ELSE 0 END)           AS nullable_columns,
    SUM(CASE WHEN virtual_column = 'YES' THEN 1 ELSE 0 END)   AS virtual_columns,
    SUM(CASE WHEN data_default IS NOT NULL THEN 1 ELSE 0 END) AS default_columns
FROM dba_tab_columns
WHERE owner = '&SCHEMA_NAME'
GROUP BY table_name
ORDER BY table_name;


-- =============================================================================
-- SECTION 5: PRIMARY KEY CONSTRAINTS - DETAIL
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [5] PRIMARY KEY CONSTRAINTS WITH COLUMNS
PROMPT ------------------------------------------------------------

SELECT
    c.table_name,
    c.constraint_name,
    c.status,
    c.validated,
    c.rely,
    LISTAGG(cc.column_name, ', ')
        WITHIN GROUP (ORDER BY cc.position)  AS pk_columns
FROM dba_constraints  c
JOIN dba_cons_columns cc
    ON  cc.owner           = c.owner
    AND cc.constraint_name = c.constraint_name
WHERE c.owner           = '&SCHEMA_NAME'
  AND c.constraint_type = 'P'
GROUP BY c.table_name, c.constraint_name, c.status, c.validated, c.rely
ORDER BY c.table_name;


-- =============================================================================
-- SECTION 6: FOREIGN KEY CONSTRAINTS - DETAIL
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [6] FOREIGN KEY CONSTRAINTS WITH PARENT REFERENCES
PROMPT ------------------------------------------------------------

SELECT
    c.table_name,
    c.constraint_name,
    c.status,
    c.validated,
    c.delete_rule,
    rc.table_name   AS referenced_table,
    rc.constraint_name AS referenced_pk,
    LISTAGG(cc.column_name, ', ')
        WITHIN GROUP (ORDER BY cc.position) AS fk_columns
FROM dba_constraints  c
JOIN dba_cons_columns cc
    ON  cc.owner           = c.owner
    AND cc.constraint_name = c.constraint_name
JOIN dba_constraints  rc
    ON  rc.owner           = c.r_owner
    AND rc.constraint_name = c.r_constraint_name
WHERE c.owner           = '&SCHEMA_NAME'
  AND c.constraint_type = 'R'
GROUP BY c.table_name, c.constraint_name, c.status, c.validated,
         c.delete_rule, rc.table_name, rc.constraint_name
ORDER BY c.table_name;


-- =============================================================================
-- SECTION 7: UNIQUE CONSTRAINTS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [7] UNIQUE CONSTRAINTS
PROMPT ------------------------------------------------------------

SELECT
    c.table_name,
    c.constraint_name,
    c.status,
    c.validated,
    LISTAGG(cc.column_name, ', ')
        WITHIN GROUP (ORDER BY cc.position) AS unique_columns
FROM dba_constraints  c
JOIN dba_cons_columns cc
    ON  cc.owner           = c.owner
    AND cc.constraint_name = c.constraint_name
WHERE c.owner           = '&SCHEMA_NAME'
  AND c.constraint_type = 'U'
GROUP BY c.table_name, c.constraint_name, c.status, c.validated
ORDER BY c.table_name;


-- =============================================================================
-- SECTION 8: DISABLED / INVALID CONSTRAINTS (Must be investigated)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [8] DISABLED OR INVALID CONSTRAINTS  -- Investigate these
PROMPT ------------------------------------------------------------

SELECT
    table_name,
    constraint_name,
    constraint_type,
    status,
    validated,
    last_change
FROM dba_constraints
WHERE owner = '&SCHEMA_NAME'
  AND (status    = 'DISABLED' OR validated = 'NOT VALIDATED')
ORDER BY table_name, constraint_type;


-- =============================================================================
-- SECTION 9: INDEX DETAILS WITH COLUMNS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [9] INDEX DETAILS WITH INDEXED COLUMNS
PROMPT ------------------------------------------------------------

SELECT
    i.table_name,
    i.index_name,
    i.index_type,
    i.uniqueness,
    i.status,
    i.partitioned,
    i.visibility,
    LISTAGG(ic.column_name || DECODE(ic.descend,'DESC',' DESC',''), ', ')
        WITHIN GROUP (ORDER BY ic.column_position) AS indexed_columns
FROM dba_indexes     i
JOIN dba_ind_columns ic
    ON  ic.index_owner = i.owner
    AND ic.index_name  = i.index_name
WHERE i.table_owner = '&SCHEMA_NAME'
GROUP BY i.table_name, i.index_name, i.index_type,
         i.uniqueness, i.status, i.partitioned, i.visibility
ORDER BY i.table_name, i.index_name;


-- =============================================================================
-- SECTION 10: UNUSABLE INDEXES (Critical — query performance impact)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [10] UNUSABLE INDEXES  -- Must be ZERO on Target
PROMPT ------------------------------------------------------------

SELECT
    index_name,
    table_name,
    index_type,
    status,
    partitioned
FROM dba_indexes
WHERE table_owner = '&SCHEMA_NAME'
  AND status      = 'UNUSABLE'
ORDER BY table_name;

-- Also check partitioned index partitions
SELECT
    ip.index_name,
    ip.partition_name,
    ip.status,
    i.table_name
FROM dba_ind_partitions ip
JOIN dba_indexes i
    ON  i.owner      = ip.index_owner
    AND i.index_name = ip.index_name
WHERE i.table_owner = '&SCHEMA_NAME'
  AND ip.status     = 'UNUSABLE'
ORDER BY ip.index_name, ip.partition_name;


-- =============================================================================
-- SECTION 11: PACKAGE / PROCEDURE / FUNCTION SOURCE LINE COUNT
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [11] CODE OBJECT LINE COUNTS
PROMPT  (Compare line counts between Source and Target)
PROMPT ------------------------------------------------------------

SELECT
    name           AS object_name,
    type           AS object_type,
    COUNT(*)       AS source_lines
FROM dba_source
WHERE owner = '&SCHEMA_NAME'
GROUP BY name, type
ORDER BY type, name;


-- =============================================================================
-- SECTION 12: PACKAGE SPEC vs BODY MISMATCH CHECK
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [12] PACKAGE SPEC WITHOUT BODY (or vice versa)  -- Should be empty
PROMPT ------------------------------------------------------------

SELECT
    spec.object_name,
    CASE WHEN spec.object_type IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS spec_status,
    CASE WHEN body.object_type IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS body_status
FROM
    (SELECT object_name, object_type FROM dba_objects
     WHERE owner = '&SCHEMA_NAME' AND object_type = 'PACKAGE') spec
FULL OUTER JOIN
    (SELECT object_name, object_type FROM dba_objects
     WHERE owner = '&SCHEMA_NAME' AND object_type = 'PACKAGE BODY') body
ON spec.object_name = body.object_name
WHERE spec.object_type IS NULL OR body.object_type IS NULL
ORDER BY spec.object_name;


-- =============================================================================
-- SECTION 13: TYPE SPEC vs BODY MISMATCH
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [13] TYPE SPEC WITHOUT BODY (or vice versa)  -- Should be empty
PROMPT ------------------------------------------------------------

SELECT
    spec.object_name,
    CASE WHEN spec.object_type IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS spec_status,
    CASE WHEN body.object_type IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS body_status
FROM
    (SELECT object_name, object_type FROM dba_objects
     WHERE owner = '&SCHEMA_NAME' AND object_type = 'TYPE') spec
FULL OUTER JOIN
    (SELECT object_name, object_type FROM dba_objects
     WHERE owner = '&SCHEMA_NAME' AND object_type = 'TYPE BODY') body
ON spec.object_name = body.object_name
WHERE spec.object_type IS NULL OR body.object_type IS NULL
ORDER BY spec.object_name;


-- =============================================================================
-- SECTION 14: COMPILATION ERRORS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [14] COMPILATION ERRORS IN CODE OBJECTS  -- Should be ZERO
PROMPT ------------------------------------------------------------

SELECT
    owner,
    name           AS object_name,
    type           AS object_type,
    line,
    position,
    text           AS error_message,
    attribute
FROM dba_errors
WHERE owner = '&SCHEMA_NAME'
ORDER BY name, type, line, position;


-- =============================================================================
-- SECTION 15: TRIGGER DETAILS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [15] TRIGGER FULL DETAILS
PROMPT ------------------------------------------------------------

SELECT
    trigger_name,
    trigger_type,
    triggering_event,
    table_name,
    base_object_type,
    column_name,
    referencing_names,
    status,
    action_type
FROM dba_triggers
WHERE owner = '&SCHEMA_NAME'
ORDER BY table_name, trigger_name;


-- =============================================================================
-- SECTION 16: VIEW DEFINITIONS (First 200 chars for spot check)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [16] VIEW DEFINITIONS (Truncated to 200 chars for comparison)
PROMPT ------------------------------------------------------------

SELECT
    view_name,
    text_length,
    SUBSTR(text, 1, 200) AS view_text_preview
FROM dba_views
WHERE owner = '&SCHEMA_NAME'
ORDER BY view_name;


-- =============================================================================
-- SECTION 17: MATERIALIZED VIEW FULL DETAILS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [17] MATERIALIZED VIEW DETAILS + LOG CHECK
PROMPT ------------------------------------------------------------

SELECT
    mv.mview_name,
    mv.container_name,
    mv.query_len,
    mv.refresh_mode,
    mv.refresh_method,
    mv.build_mode,
    mv.fast_refreshable,
    mv.last_refresh_type,
    mv.staleness,
    mv.compile_state,
    CASE WHEN ml.log_table IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_mview_log
FROM dba_mviews mv
LEFT JOIN dba_mview_logs ml
    ON  ml.log_owner = mv.owner
    AND ml.master    = mv.mview_name
WHERE mv.owner = '&SCHEMA_NAME'
ORDER BY mv.mview_name;


-- =============================================================================
-- SECTION 18: SEQUENCE CURRENT VALUES (compare drift after migration)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [18] SEQUENCE CURRENT STATE
PROMPT ------------------------------------------------------------

SELECT
    sequence_name,
    min_value,
    max_value,
    increment_by,
    cycle_flag,
    order_flag,
    cache_size,
    last_number,
    -- Gap to max (useful for checking exhaustion risk)
    CASE WHEN max_value = 9999999999999999999999999999 THEN 'NO LIMIT'
         ELSE TO_CHAR(ROUND((max_value - last_number) / GREATEST(increment_by,1)))
    END AS remaining_values
FROM dba_sequences
WHERE sequence_owner = '&SCHEMA_NAME'
ORDER BY sequence_name;


-- =============================================================================
-- SECTION 19: PARTITIONED TABLES
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [19] PARTITIONED TABLE DETAILS
PROMPT ------------------------------------------------------------

SELECT
    pt.table_name,
    pt.partitioning_type,
    pt.subpartitioning_type,
    pt.partition_count,
    pt.def_subpartition_count,
    pt.interval
FROM dba_part_tables pt
WHERE pt.owner = '&SCHEMA_NAME'
ORDER BY pt.table_name;

-- Partition-level details
SELECT
    tp.table_name,
    tp.partition_name,
    tp.partition_position,
    tp.high_value,
    tp.num_rows,
    tp.blocks,
    ROUND(s.bytes/1024/1024,2) AS segment_size_mb,
    tp.last_analyzed
FROM dba_tab_partitions tp
LEFT JOIN dba_segments s
    ON  s.owner          = tp.table_owner
    AND s.segment_name   = tp.table_name
    AND s.partition_name = tp.partition_name
WHERE tp.table_owner = '&SCHEMA_NAME'
ORDER BY tp.table_name, tp.partition_position;


-- =============================================================================
-- SECTION 20: LOB COLUMNS (CLOBs, BLOBs, NCLOBs)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [20] LOB COLUMN DETAILS
PROMPT ------------------------------------------------------------

SELECT
    l.table_name,
    l.column_name,
    l.lob_name,
    l.index_name,
    l.chunk,
    l.pctversion,
    l.cache,
    l.in_row,
    l.storage_spec,
    l.retention,
    l.freepools
FROM dba_lobs l
WHERE l.owner = '&SCHEMA_NAME'
ORDER BY l.table_name, l.column_name;


-- =============================================================================
-- SECTION 21: DATA TYPE DISTRIBUTION (Cross-table analysis)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [21] DATA TYPE DISTRIBUTION ACROSS ALL TABLES
PROMPT ------------------------------------------------------------

SELECT
    data_type,
    COUNT(*)                         AS column_count,
    COUNT(DISTINCT table_name)       AS tables_using_type,
    MIN(data_length)                 AS min_length,
    MAX(data_length)                 AS max_length,
    MIN(data_precision)              AS min_precision,
    MAX(data_precision)              AS max_precision
FROM dba_tab_columns
WHERE owner = '&SCHEMA_NAME'
GROUP BY data_type
ORDER BY column_count DESC;


-- =============================================================================
-- SECTION 22: GRANTS ON DVM OBJECTS TO OTHER SCHEMAS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [22] ALL GRANTS ON DVM OBJECTS (to other users/roles)
PROMPT ------------------------------------------------------------

SELECT
    grantee,
    owner,
    table_name           AS object_name,
    privilege,
    grantable,
    hierarchy,
    type
FROM dba_tab_privs
WHERE owner   = '&SCHEMA_NAME'
  AND grantee != '&SCHEMA_NAME'
ORDER BY grantee, table_name, privilege;


-- =============================================================================
-- SECTION 23: COLUMN-LEVEL GRANTS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [23] COLUMN-LEVEL GRANTS ON DVM OBJECTS
PROMPT ------------------------------------------------------------

SELECT
    grantee,
    owner,
    table_name,
    column_name,
    privilege,
    grantable
FROM dba_col_privs
WHERE owner = '&SCHEMA_NAME'
ORDER BY table_name, column_name, grantee;


-- =============================================================================
-- SECTION 24: STATISTICS FRESHNESS CHECK
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [24] TABLE STATISTICS FRESHNESS
PROMPT  (Stale stats can cause query plan issues on RDS)
PROMPT ------------------------------------------------------------

SELECT
    table_name,
    num_rows,
    blocks,
    avg_row_len,
    TO_CHAR(last_analyzed,'YYYY-MM-DD HH24:MI:SS') AS last_analyzed,
    stale_stats,
    stattype_locked
FROM dba_tab_statistics
WHERE owner = '&SCHEMA_NAME'
ORDER BY last_analyzed NULLS FIRST;


-- =============================================================================
-- SECTION 25: SCHEDULER JOB DETAILS
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [25] SCHEDULER JOB FULL DETAILS
PROMPT ------------------------------------------------------------

SELECT
    job_name,
    job_class,
    job_type,
    job_action,
    schedule_type,
    repeat_interval,
    max_failures,
    max_runs,
    state,
    enabled,
    restartable,
    TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS')  AS last_run,
    TO_CHAR(next_run_date,   'YYYY-MM-DD HH24:MI:SS')  AS next_run,
    run_count,
    failure_count
FROM dba_scheduler_jobs
WHERE owner = '&SCHEMA_NAME'
ORDER BY job_name;


-- =============================================================================
-- SECTION 26: NULL DENSITY & COLUMN STATISTICS (spot check data quality)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [26] COLUMN STATISTICS (Num Distinct, Nulls, Density)
PROMPT      Compare between Source and Target for data quality
PROMPT ------------------------------------------------------------

SELECT
    cs.table_name,
    cs.column_name,
    cs.num_distinct,
    cs.num_nulls,
    cs.density,
    cs.avg_col_len,
    cs.low_value,
    cs.high_value,
    TO_CHAR(cs.last_analyzed,'YYYY-MM-DD') AS last_analyzed
FROM dba_tab_col_statistics cs
WHERE cs.owner = '&SCHEMA_NAME'
ORDER BY cs.table_name, cs.column_name;


-- =============================================================================
-- SECTION 27: REFERENTIAL INTEGRITY ORPHAN CHECK
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [27] FK ORPHAN ROW CHECK (Dynamic — runs for each FK)
PROMPT  Identifies child rows with no matching parent row
PROMPT ------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
    v_sql       VARCHAR2(4000);
    v_count     NUMBER;
    v_child_col VARCHAR2(4000);
    v_par_col   VARCHAR2(4000);
BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD('CHILD TABLE', 35) || ' | ' ||
                         RPAD('FK NAME', 35)     || ' | ' ||
                         RPAD('PARENT TABLE', 35) || ' | ' ||
                         LPAD('ORPHAN_ROWS', 12));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 125, '-'));

    FOR fk IN (
        SELECT
            c.table_name     AS child_table,
            c.constraint_name,
            rc.table_name    AS parent_table,
            c.owner,
            c.r_owner,
            c.r_constraint_name
        FROM   dba_constraints c
        JOIN   dba_constraints rc
            ON  rc.owner           = c.r_owner
            AND rc.constraint_name = c.r_constraint_name
        WHERE  c.owner           = '&SCHEMA_NAME'
          AND  c.constraint_type = 'R'
          AND  c.status          = 'ENABLED'
    ) LOOP
        -- Build column lists
        SELECT LISTAGG('c.' || cc.column_name, ', ')
                   WITHIN GROUP (ORDER BY cc.position)
        INTO   v_child_col
        FROM   dba_cons_columns cc
        WHERE  cc.owner           = fk.owner
          AND  cc.constraint_name = fk.constraint_name;

        SELECT LISTAGG('p.' || cc.column_name, ', ')
                   WITHIN GROUP (ORDER BY cc.position)
        INTO   v_par_col
        FROM   dba_cons_columns cc
        WHERE  cc.owner           = fk.r_owner
          AND  cc.constraint_name = fk.r_constraint_name;

        -- Build orphan check query
        v_sql :=
            'SELECT COUNT(*) FROM &SCHEMA_NAME.' || fk.child_table || ' c ' ||
            'WHERE NOT EXISTS (' ||
            '  SELECT 1 FROM &SCHEMA_NAME.' || fk.parent_table || ' p ' ||
            '  WHERE (' || v_par_col || ') = (' || v_child_col || '))' ||
            ' AND (' || v_child_col || ') IS NOT NULL';

        BEGIN
            EXECUTE IMMEDIATE v_sql INTO v_count;
            IF v_count > 0 THEN
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(fk.child_table,      35) || ' | ' ||
                    RPAD(fk.constraint_name,  35) || ' | ' ||
                    RPAD(fk.parent_table,     35) || ' | ' ||
                    LPAD(v_count, 12) || '  <== ORPHANS FOUND!'
                );
            ELSE
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(fk.child_table,      35) || ' | ' ||
                    RPAD(fk.constraint_name,  35) || ' | ' ||
                    RPAD(fk.parent_table,     35) || ' | ' ||
                    LPAD('0 (OK)', 12)
                );
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(fk.child_table, 35) || ' | ERROR: ' || SQLERRM
                );
        END;
    END LOOP;
END;
/


-- =============================================================================
-- SECTION 28: DUPLICATE PRIMARY KEY CHECK
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [28] DUPLICATE PRIMARY KEY CHECK (Dynamic)
PROMPT  Should return ZERO rows everywhere
PROMPT ------------------------------------------------------------

DECLARE
    v_sql       VARCHAR2(4000);
    v_count     NUMBER;
    v_pk_cols   VARCHAR2(2000);
BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD('TABLE_NAME', 40) || ' | ' ||
                         RPAD('PK_COLUMNS', 60) || ' | ' ||
                         LPAD('DUPLICATE_GROUPS', 16));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 125, '-'));

    FOR pk IN (
        SELECT
            c.table_name,
            c.constraint_name
        FROM dba_constraints c
        WHERE c.owner           = '&SCHEMA_NAME'
          AND c.constraint_type = 'P'
    ) LOOP
        SELECT LISTAGG(cc.column_name, ', ')
                   WITHIN GROUP (ORDER BY cc.position)
        INTO   v_pk_cols
        FROM   dba_cons_columns cc
        WHERE  cc.owner           = '&SCHEMA_NAME'
          AND  cc.constraint_name = pk.constraint_name;

        v_sql :=
            'SELECT COUNT(*) FROM (' ||
            '  SELECT ' || v_pk_cols || ', COUNT(*) AS cnt ' ||
            '  FROM &SCHEMA_NAME.' || pk.table_name ||
            '  GROUP BY ' || v_pk_cols ||
            '  HAVING COUNT(*) > 1)';

        BEGIN
            EXECUTE IMMEDIATE v_sql INTO v_count;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(pk.table_name,  40) || ' | ' ||
                RPAD(v_pk_cols,      60) || ' | ' ||
                LPAD(CASE WHEN v_count > 0
                          THEN v_count || ' <== DUPLICATES!'
                          ELSE '0 (OK)'
                     END, 16)
            );
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(pk.table_name, 40) || ' | ERROR: ' || SQLERRM
                );
        END;
    END LOOP;
END;
/


-- =============================================================================
-- SECTION 29: NULL CHECK ON NOT-NULL COLUMNS (Data Integrity Guard)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [29] NULL VALUES IN NOT-NULL COLUMNS (Dynamic)
PROMPT  Should return ZERO everywhere — critical integrity check
PROMPT ------------------------------------------------------------

DECLARE
    v_sql   VARCHAR2(2000);
    v_count NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD('TABLE_NAME', 40) || ' | ' ||
                         RPAD('COLUMN_NAME', 40) || ' | ' ||
                         LPAD('NULL_COUNT', 12));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));

    FOR col IN (
        SELECT table_name, column_name
        FROM   dba_tab_columns
        WHERE  owner    = '&SCHEMA_NAME'
          AND  nullable = 'N'
          AND  virtual_column = 'NO'
    ) LOOP
        v_sql := 'SELECT COUNT(*) FROM &SCHEMA_NAME.' ||
                 col.table_name || ' WHERE ' ||
                 col.column_name || ' IS NULL';
        BEGIN
            EXECUTE IMMEDIATE v_sql INTO v_count;
            IF v_count > 0 THEN
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(col.table_name,  40) || ' | ' ||
                    RPAD(col.column_name, 40) || ' | ' ||
                    LPAD(v_count || ' <== NULLS!', 12)
                );
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Done. No output above means all NOT NULL columns are clean.');
END;
/


-- =============================================================================
-- SECTION 30: OBJECT DEPENDENCY MAP
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [30] OBJECT DEPENDENCY MAP
PROMPT  (Verify all dependent objects resolve correctly)
PROMPT ------------------------------------------------------------

SELECT
    d.name           AS object_name,
    d.type           AS object_type,
    d.referenced_name,
    d.referenced_type,
    d.referenced_owner,
    d.dependency_type
FROM dba_dependencies d
WHERE d.owner = '&SCHEMA_NAME'
  AND d.referenced_owner NOT IN (
        'SYS','SYSTEM','PUBLIC','WMSYS','XDB','MDSYS',
        'CTXSYS','ORDSYS','EXFSYS','DBMS_METADATA'
      )
ORDER BY d.type, d.name, d.referenced_type, d.referenced_name;


-- =============================================================================
-- SECTION 31: MISSING OBJECT REFERENCES (Broken Dependencies)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [31] BROKEN DEPENDENCIES (Objects referenced but not found)
PROMPT  These indicate migration gaps
PROMPT ------------------------------------------------------------

SELECT DISTINCT
    d.name               AS object_with_broken_dep,
    d.type               AS object_type,
    d.referenced_name    AS missing_object,
    d.referenced_type    AS missing_type,
    d.referenced_owner   AS missing_owner
FROM dba_dependencies d
WHERE d.owner = '&SCHEMA_NAME'
  AND NOT EXISTS (
        SELECT 1 FROM dba_objects o
        WHERE o.owner       = d.referenced_owner
          AND o.object_name = d.referenced_name
          AND o.object_type LIKE d.referenced_type || '%'
      )
  AND d.referenced_owner NOT IN ('SYS','SYSTEM','PUBLIC')
ORDER BY d.name;


-- =============================================================================
-- SECTION 32: AUDIT SETTINGS (RDS-specific — may differ from on-prem)
-- =============================================================================
PROMPT
PROMPT ------------------------------------------------------------
PROMPT  [32] AUDIT SETTINGS ON DVM OBJECTS
PROMPT ------------------------------------------------------------

SELECT
    user_name,
    proxy_name,
    audit_option,
    success,
    failure
FROM dba_stmt_audit_opts
WHERE user_name = '&SCHEMA_NAME';

SELECT
    object_schema,
    object_name,
    object_type,
    ins,del,upd,sel,exe,fbk,rea
FROM dba_obj_audit_opts
WHERE object_schema = '&SCHEMA_NAME'
ORDER BY object_name;


-- =============================================================================
-- SECTION 33: COMPREHENSIVE VALIDATION SCORECARD
-- =============================================================================
PROMPT
PROMPT ============================================================
PROMPT  [33] COMPREHENSIVE SCORECARD SUMMARY
PROMPT ============================================================

SELECT 'TABLES'              AS category, COUNT(*) AS count FROM dba_tables      WHERE owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'VIEWS',               COUNT(*) FROM dba_views        WHERE owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'INDEXES',             COUNT(*) FROM dba_indexes       WHERE table_owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'PROCEDURES',          COUNT(*) FROM dba_objects       WHERE owner = '&SCHEMA_NAME' AND object_type = 'PROCEDURE'
UNION ALL
SELECT 'FUNCTIONS',           COUNT(*) FROM dba_objects       WHERE owner = '&SCHEMA_NAME' AND object_type = 'FUNCTION'
UNION ALL
SELECT 'PACKAGES',            COUNT(*) FROM dba_objects       WHERE owner = '&SCHEMA_NAME' AND object_type = 'PACKAGE'
UNION ALL
SELECT 'PACKAGE BODIES',      COUNT(*) FROM dba_objects       WHERE owner = '&SCHEMA_NAME' AND object_type = 'PACKAGE BODY'
UNION ALL
SELECT 'TRIGGERS',            COUNT(*) FROM dba_triggers      WHERE owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'SEQUENCES',           COUNT(*) FROM dba_sequences     WHERE sequence_owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'SYNONYMS',            COUNT(*) FROM dba_synonyms      WHERE owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'TYPES',               COUNT(*) FROM dba_objects       WHERE owner = '&SCHEMA_NAME' AND object_type = 'TYPE'
UNION ALL
SELECT 'MAT VIEWS',           COUNT(*) FROM dba_mviews        WHERE owner = '&SCHEMA_NAME'
UNION ALL
SELECT 'INVALID OBJECTS',     COUNT(*) FROM dba_objects       WHERE owner = '&SCHEMA_NAME' AND status = 'INVALID'
UNION ALL
SELECT 'DISABLED CONSTRAINTS',COUNT(*) FROM dba_constraints   WHERE owner = '&SCHEMA_NAME' AND status = 'DISABLED'
UNION ALL
SELECT 'UNUSABLE INDEXES',    COUNT(*) FROM dba_indexes        WHERE table_owner = '&SCHEMA_NAME' AND status = 'UNUSABLE'
UNION ALL
SELECT 'COMPILE ERRORS',      COUNT(*) FROM dba_errors        WHERE owner = '&SCHEMA_NAME'
ORDER BY category;

PROMPT
PROMPT ============================================================
PROMPT  END OF LEVEL 2 COMPREHENSIVE VALIDATION REPORT
PROMPT ============================================================

SPOOL OFF
