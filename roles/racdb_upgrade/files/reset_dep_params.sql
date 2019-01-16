rem ============================================================================
rem
rem Purpose  : Script to remove deprecated database parameters.
rem ============================================================================
rem

set pause off
set lines 130
set pages 9999
set heading off
set feedback off
set showmode off
set echo off
set verify off
set serverout on size unlimited
set termout off

DECLARE
   l_sql   VARCHAR2 (200);

   CURSOR c_deprec_param
   IS
      SELECT SID, NAME, VALUE
        FROM v$spparameter
       WHERE NAME IN (SELECT NAME
                        FROM v$parameter
                       WHERE isdeprecated = 'TRUE') AND VALUE IS NOT NULL;
BEGIN
   for r_deprec_param in c_deprec_param
   loop
     l_sql := 'alter system reset '||r_deprec_param.name||' scope=spfile sid='''||r_deprec_param.sid||'''';
--     dbms_output.put_line(l_sql);
     execute immediate (l_sql);
   end loop;
END;
/
