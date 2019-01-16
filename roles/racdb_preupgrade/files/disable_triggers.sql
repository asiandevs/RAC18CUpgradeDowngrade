set lines 2000
set pages 0
set heading off
set feed off
set trimspool on
spool disable_triggers.txt
select 'alter trigger '||OWNER||'.'||TRIGGER_NAME||' disable;' from dba_triggers where status = 'ENABLED' and owner not in ('SYSTEM','EXFSYS','XDB','SYS','MDSYS');
spool off
spool enable_triggers.txt
select 'alter trigger '||OWNER||'.'||TRIGGER_NAME||' enable;' from dba_triggers where status = 'ENABLED' and owner not in ('SYSTEM','EXFSYS','XDB','SYS','MDSYS');
spool off
