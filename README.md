## RAC Database Upgrade with Pluggable database from 12c ---> 18C and Rollback [Downgrade to] to 12c
This is for RAC database upgrade from 12.2 to 18.3 and downgrade from 18.3 to 12.2

### You can use this for other versions also --- make sure you setup all the variables and value - as an example current version (19..) and target version (21..)

```diff
- NOTE
! Make sure any Licence requirements from your side. Please do modify based on your own setup. This is purely based on my own lab setup. You can ask me any questions in relate to these playbooks - if you fork and modify to merge - let me know.
```

```
References
# How to Download and Run Oracle's Database Pre-Upgrade Utility (Doc ID 884522.1)
# Scripts to automatically update the RDBMS DST (timezone) version in an 11gR2 or 12c database . (Doc ID 1585343.1)
# Database Upgrade Guide: https://docs.oracle.com/en/database/oracle/oracle-database/18/upgrd

```
```

## Roles

roles                  | tasks
---------------------- | ----------------------------------------------------------------------
racdb_preupgrade       |  **Pre Upgrade script**
racdb_upgrade          |  **Upgrade RAC 12.2 CDB Database to 18.3 with one pluggable database PDB**
racdb_predwngrade      |  **Prep Downgrade script**
racdb_dwngrade         |  **Downgrade Oracle 18.3 database to 12.2 version using Flashback with minimum outage*

```

```
Ansible role, racdb_prepupgrade :
Script steps  : 1  : Compile invalid objects before upgrade
                2  : Create script to disable user triggers]
                3  : Disable concurrent statistics gathering]
                4  : run database health check
                5  : Disable concurrent statistics gathering
                6  : Validate the integrity of the source database
                7  : Open pluggable database if not open
                8  : extract preupgrade zipped roles
                9  : execute jar file preupgrade
                10 : Execute preupgrade fixups
		11 : validate integrity of the source database
                12 : Purge the Recyclebin
                13 : Gather dictionary statistics
                14 : report invalid objects
```
```
Variables
src_scripts_dir:   "/etc/ansible/roles/racdb_upgrade/files"
oracle_base:       /u01/app/oracle
old_oracle_home:   /u01/app/oracle/product/12.2.0/db100
target_dbuname:    PMON1_01
target_dbname:     PMON1
root_user:         root
oracle_sid:        PMON11
new_oracle_home:   /u02/app/oracle/product/18.3.0/dbhome_1
jdk_dir:           /u02/app/oracle/product/18.3.0/dbhome_1/jdk
logdir:            /tmp/18cCDBUPGRD/{{ oracle_sid }}
oratab:            "/etc/oratab"
RESTORE_POINT:     "BEFORE_UPGRADE"
CLUSTER:           "racdb01"
PDB_NAME:          "PMON1PDB"
```
```
Ansible role, racdb_upgrade :
Script steps  : 1  : Disable user triggers
                2  : Remove deprecated parameters
                3  : Compile invalid objects before upgrade
                4  : Report invalid objects before upgrade
                5  : disable cluster_database database parameter
                6  : disable database
		7  : Stop cluster database
               	8  : Copy database related files to New Home
		9  : Modify oratab
                10 : Start database in upgrade mode
                11 : Create guaranteed restore point for rollback
                12 : Execute catupgrd.sql script to upgrade the database to 18c
		13 : Update timezone file version of the pdb database
		14 : Update timezone file version of the pdb database
                15 : Start database in normal mode again
                16 : Execute post upgrade script postupgrade_fixups
		17 : Execute post upgrade script exec_utlu122s.sql
                18 : Execute post upgrade script catuppst.sql
		19 : Validate the integrity of the source database
                20 : Compile invalid objects after upgrade
		21 : Enable user trigger
		22 : Modify CRS database configuration with new ORACLE_HOME
		23 : Enable cluster_database database parameter 
		24 : Enable cluster database
		25 : Start cluster database using srvctl 
		26 : Show database components
```
```
Ansible role, racdb_predwngrade :
Script steps  : 1  : Compile invalid objects before upgrade
                2  : Create script to disable user triggers]
                3  : Validate the integrity of the source database
                4  : Purge the Recyclebin
                5  : Report invalid objects
                6  : report database components
 ```
 ```
Variables:		  
oracle_base:        /u01/app/oracle
new_oracle_home:    /u01/app/oracle/product/12.2.0/db100
stage_dir:          /u01/stage
scripts_dir:        " {{ stage_dir }}"
target_dbuname:     PMON1_01
target_dbname:      PMON1
oracle_sid:        PMON11
old_oracle_home:    /u02/app/oracle/product/18.3.0/dbhome_1
logdir:             /tmp/18cCDBDWNGRD/{{ oracle_sid }}
oratab:             "/etc/oratab"
RESTORE_POINT:      "BEFORE_UPGRADE"
CLUSTER:            "racdb01"
PDB_NAME:           "PMON1PDB"
OLD_VERSION:        "12.2.0.1.0"
```
```			
Ansible role, racdb_dwngrade:
Script steps  : 1  : Disable triggers
                2  : Disable database parameter cluster_database
                3  : Compile invalid objects before downgrade
                4  : Report invalid objects before downgrade
                5  : Stop database with srvctl
                6  : Move database related files to new ORACLE_HOME
                7  : Disable Cluster database
                8  : Stop cluster database
                9  : Flashback Pluggable database 
                10 : Flashback Container database 
                11 : Copy database related files to New Home
		12 : Modify oratab
                13 : Resetlogs after Flashback Container database
                14 : Start database using sqlplus 
                15 : Enable user trigger 
                16 : Modify CRS database configuration with new ORACLE_HOME
		17 :Enable cluster_database database parameter
		18 :enable cluster database
                19 : Start downgraded database from new ORACLE_HOME with srvctl
                20 : drop Guarantee Restore Point for CDB and PDB
                21 : Show database components
 ```               
