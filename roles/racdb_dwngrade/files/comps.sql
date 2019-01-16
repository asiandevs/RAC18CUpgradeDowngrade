set linesize 180
set pagesize 1000
column comp_id format a15
column comp_name format a40
column version format a15
column status format a12
select comp_id, comp_name, version, status from sys.dba_registry;
