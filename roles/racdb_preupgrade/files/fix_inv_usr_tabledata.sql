@utluppkg.sql
SET SERVEROUTPUT ON;
exec dbms_preup.run_fixup_and_report('INVALID_USR_TABLEDATA');
SET SERVEROUTPUT OFF;

