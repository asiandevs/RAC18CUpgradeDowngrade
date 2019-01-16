#!/bin/sh
# Script        : drop_restore_point.sh
# Purpose       : see usage
# Usage         : see usage
# ***************************************************************************************************************
# * Date        Version Name      Change                                                                    *
# * -----------  -----  ---------- ---------------------------------------------------------------------------- *
# * 2016/06/03   1.00   Monowar Mukul  Initial TEST version                                                       *
# ***************************************************************************************************************

#set -vx

usage () {

echo "

Purpose       : $0
                Drop the restore point created for the database upgrade.

Prerequisite  : Databases must be running

Usage         : $0 [-h|-d|-s|-e]

Flags         : -d database name of the database to drop restore point
                -s step to start with (optional)
                -e step to end with (optional)
                -h help

Examples      : $0 -d ADBA1 (all drop restore steps will be executed)
                $0 -d ADBA1 -s 5 (all drop restore steps starting with step 5 will be executed)
                $0 -d ADBA1 5 -e 7 (all drop restore steps starting with step 5 up and until step 7 will be executed)


               Show usage
               $0 -h

Script steps  : 1  : Determine Database Type 
                2  : Stop apply on standby database 
                3  : Disable and Stop database with srvctl
                4  : Start database in mount mode to drop restore point
                5  : Drop restore point in standby database
                6  : Shutdown standby database after drop restore point
                7  : Enable and Start stanby database with srvctl
                8  : Drop restore point in primary database
                9  : Show broker configuration
                10 : Zip logfile directory for upload to ServiceNow

"
}

while getopts ":h:s:e:o:i:d:" opt
do
        case $opt in

            h)  usage
                exit 0
                ;;
            d)  TARGET_DBNAME=`echo ${OPTARG} | tr '[:lower:]' '[:upper:]'`
                export TARGET_DBNAME
                ;;
            i)  TARGET_SID=`echo ${OPTARG} | tr '[:lower:]' '[:upper:]'`
                export TARGET_SID
                ;;
            o)  NEW_ORACLE_HOME=${OPTARG}
                ;;
            s)  STEP=${OPTARG}
                ;;
            e)  ENDSTEP=${OPTARG}
                ;;
            *)  usage
                exit 1
                ;;
        esac
done

if [ -z "$1" ];
then
  echo "No parameters are provided."
  usage
  exit 1
fi

function LogMsg ()
{
  LogMsgTimestamp=`date "+%Y-%m-%d %T"`

# if they are piping in the message to print from a command
# (ie, cat file | LogMsg).  this requires resetting the interfield
# separator...
  if [ "$1" = "-p" ]; then
    tmp="$IFS"
    IFS=""
    while read message
    do
      printf "%s %s \n" "${message}"
      if [[ ! -z "$LOGFILE" ]]; then
         printf "%s %s %s \n" $LogMsgTimestamp "${message}" >> $LOGFILE
      fi
    done
    IFS="$tmp"
  else
    printf "%s %s \n" "$1"
    if [[ ! -z "$LOGFILE" ]]; then
       printf "%s %s %s \n" $LogMsgTimestamp "$1" >> $LOGFILE
    fi
  fi
}

set_vars ()
{
  ORATAB=/etc/oratab
  GIHOME=$(grep ^+ASM ${ORATAB} | awk -F: {'print $2'})
  TARGET_DBUNNAME=$($GIHOME/bin/srvctl config database | grep ${TARGET_DBNAME})
  export ORATAB=/etc/oratab
  if [ -z "${TARGET_SID}" ];
  then
    TARGET_SID=$(ps -ef|grep pm[o]n|grep ${TARGET_DBNAME}|grep -v tfa|awk '{print substr($NF,10)}')
  fi
  CLUSTER=$($GIHOME/bin/olsnodes -c)
  LogTimestamp=$(date +%Y%m%d_%H%M%S)
  WORKDIR=/iorsdb_apac_migration/12cUPGRADE/${TARGET_DBNAME}
  LOGFILE=${WORKDIR}/drop_restore_point_${TARGET_DBNAME}_${LogTimestamp}.log
  tmpstr=""
  STEP="${STEP:-1}"
  ENDSTEP="${ENDSTEP:-0}"

  if [[ ${ENDSTEP} -lt ${STEP} && ${ENDSTEP} -ne 0 ]];
  then
    LogMsg "End Step can't be smaller than start step"
    usage
    exit 1
  fi

  if [ ! -d $NEW_ORACLE_HOME ];
  then
    LogMsg "FATAL: ORACLE_HOME ${NEW_ORACLE_HOME} does not exist"
    exit 1;
  fi

  BHPB_DP_PARAMS="/software/deployments/.999/dp_params.pl"
  if [[ ! -r "${BHPB_DP_PARAMS}" ]]; then
    LogMsg "ERROR: parameter file '${BHPB_DP_PARAMS}' not readable."
    exit 1
  else
    LogMsg "INFO: parameter file '${BHPB_DP_PARAMS}' readable."
  fi

  PREREQS=`perl -e "require ('${BHPB_DP_PARAMS}');system('echo \\\$PREREQS');"`
  SYS_PWD=`${PREREQS} 1`
  EMCLI_HOME=`perl -e "require ('${BHPB_DP_PARAMS}');system('echo \\\$EMCLI_HOME');"`
}

show_params ()
{
  clear
  LogMsg "The following paramaters are provided and will be used to drop the restore point"
  LogMsg "${tmpstr}"
  LogMsg "Target DB_UNIQUE_NAME : $TARGET_DBUNNAME"
  LogMsg "Target DB Name        : $TARGET_DBNAME"
  LogMsg "Target Instance Name  : $TARGET_SID"
  LogMsg "Target Cluster Name   : $CLUSTER"
  LogMsg "Start step            : ${STEP}"
  if [ $ENDSTEP -eq 0 ];
  then
    LogMsg "Stop step             : All steps"
  else
    LogMsg "Stop step             : ${ENDSTEP}"
  fi

  LogMsg "${tmpstr}"
  LogMsg "Are these parameters correct? If YES, press [ENTER], if NO, press [CNTRL + C]"
  read goahead
}

setenv ()
{
  ORACLE_SID=${TARGET_SID}
  ORAENV_ASK=NO
  . oraenv >> /dev/null 2>&1
  ORAENV_ASK=YES

  RC=$?
  if [ ${RC} -ne 0 ];
  then
    LogMsg "STEP $STEP: FATAL - Environment not set to ORACLE_HOME ${ORACLE_HOME} correctly. Exiting !!!"
    exit 1;
  else
    LogMsg "STEP $STEP: INFO - Environment set to ORACLE_HOME ${ORACLE_HOME}"
  fi
}

function next_step ()
{
  if [ $STEP -eq $ENDSTEP ]; then exit 1; fi
  ((STEP++))
}

cwd ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Change active directory to working directory               #
  #                                                                       #
  #########################################################################

  if [ ! -d ${WORKDIR} ];
  then
    LogMsg "STEP $STEP: FATAL - Working directory ${WORKDIR} does not exist. Exiting !!!"
    exit 1;
  else
    cd ${WORKDIR}
    LogMsg "STEP $STEP: INFO - Changed working directory to ${WORKDIR}"
  fi

}

determine_dbtype ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Determine Database Type                                    #
  #                                                                       #
  #########################################################################

  LogMsg "STEP $STEP: Determine Database Type"
  setenv

  srvctl config database -d ${TARGET_DBUNNAME} | grep "Type:" | awk -F" " {'print $2'} > ${WORKDIR}/DBTYPE.lst

  RC=$?
  LogMsg "STEP $STEP: INFO - Exit code is $RC"
  if [ ${RC} -ne 0 ];
  then
    LogMsg "STEP $STEP: FATAL - Unable to determine database type. Exiting !!!"
    exit 1;
  else
    DBTYPE=`cat ${WORKDIR}/DBTYPE.lst`
    LogMsg "STEP $STEP: INFO - Database Type is: ${DBTYPE}"
  fi
  next_step
}

stop_apply_stby ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Stop apply on standby database                             #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    LogMsg "STEP $STEP: Stop apply on standby database ${STBYDB}"
    setenv

    dgmgrl -silent / "edit database \"${STBYDB}\" set state=APPLY-OFF;"

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to stop apply on standby database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Stopped apply on standby database ${STBYDB}"
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi
  next_step
}

disable_and_stop_cldb ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Disable and Stop database with srvctl                      #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    LogMsg "STEP $STEP: Disable database ${STBYDB} with srvctl"
    setenv

    srvctl disable database -d ${STBYDB}

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to disable database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully disabled database ${STBYDB}"
    fi

    LogMsg "STEP $STEP: Stopping database ${STBYDB} with srvctl"

    srvctl stop database -d ${STBYDB}

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to stop the database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully stopped database ${STBYDB}"
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi
  next_step
}

start_db_mount ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Start database in mount mode to drop restore point         #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    LogMsg "STEP $STEP: Start database in mount mode to drop restore point"

    sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit sql.sqlcode
    spool ${WORKDIR}/${STEP}_startup_mount_${STBYDB}.log
    startup mount
    spool off
    exit
EOF

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to start database ${STBYDB} in mount mode. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully started database ${STBYDB} in mount mode"
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi
  next_step
}

drop_restore_point_stby ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Drop restore point in standby database                     #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    LogMsg "STEP $STEP: Drop restore point in standby database ${STBYDB}"
    setenv

    sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit sql.sqlcode
    spool ${WORKDIR}/${STEP}_drop_restore_point_${STBYDB}.log
    whenever sqlerror exit sql.sqlerror
    set serverout on size unl
    set feed off
    startup mount
    declare
      l_sql varchar2(4000);
    begin
      for rec in (select name from v\$restore_point)
      loop
        l_sql := 'drop restore point '||rec.name;
        dbms_output.put_line('STEP $STEP: INFO - '||l_sql);
        execute immediate l_sql;
      end loop;
    end;
    /
    spool off
    exit
EOF

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to drop restore point in standby database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully dropped restore point in standby database ${STBYDB}"
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi
  next_step
}

shutdown_stby_db ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Shutdown standby database after drop restore point         #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    LogMsg "STEP $STEP: Shutdown standby database ${STBYDB} after drop restore point"
    setenv

    sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit sql.sqlcode
    spool ${WORKDIR}/${STEP}_stut_immediate_${STBYDB}.log
    startup mount
    spool off
    exit
EOF

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to sthutdown standby database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully shutdown standby database ${STBYDB}"
      if [ $STEP -eq $ENDSTEP ]; then exit 1; fi
      ((STEP++))
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi
  next_step
}

enable_and_start_cldb ()
{
  ##################################################################################
  #                                                                                #
  #  Purpose : Enable and Start standby database with srvctl                       #
  #                                                                                #
  ##################################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then

    LogMsg "STEP $STEP: Enable standby database i${STBYDB}with srvctl"
    setenv

    srvctl enable database -d ${STBYDB}

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to enable standby database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully enabled standby database ${STBYDB}"
    fi

    LogMsg "STEP $STEP: Start standby database ${STBYDB} with srvctl"

    DBTYPE=`cat ${WORKDIR}/DBTYPE.lst`
    if [[ ${DBTYPE} == "RAC" ]];
    then
      srvctl start database -d ${STBYDB}
    else
      srvctl start database -d ${STBYDB} -n `hostname -s`
    fi

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - An error occurred while starting standby database ${STBYDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully started standby database ${STBYDB}"
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi
  next_step
}

drop_restore_point_primary ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Drop restore point in primary database                     #
  #                                                                       #
  #########################################################################

  PRIMDB=$(cat ${WORKDIR}/PRIMDB.lst)

  if [[ $PRIMDB != "" ]];
  then
    LogMsg "STEP $STEP: Drop restore point in primary database ${PRIMDB}"
    setenv

    sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit sql.sqlcode
    spool ${WORKDIR}/${STEP}_drop_restore_point_${PRIMDB}.log
    whenever sqlerror exit sql.sqlerror
    set serverout on size unl
    set feed off
    declare
      l_sql varchar2(4000);
    begin
      for rec in (select name from v\$restore_point)
      loop
        l_sql := 'drop restore point '||rec.name;
        dbms_output.put_line('STEP $STEP: INFO - '||l_sql);
        execute immediate l_sql;
      end loop;
    end;
    /
    spool off
    exit
EOF

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to drop restore point in primary database ${PRIMDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully dropped restore point in primary database ${PRIMDB}"
    fi
  else

    LogMsg "STEP $STEP: Drop restore point in primary database ${TARGET_DBUNNAME}"
    setenv

    sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit sql.sqlcode
    spool ${WORKDIR}/${STEP}_drop_restore_point_${TARGET_DBUNNAME}.log
    whenever sqlerror exit sql.sqlerror
    set serverout on size unl
    set feed off
    declare
      l_sql varchar2(4000);
    begin
      for rec in (select name from v\$restore_point)
      loop
        l_sql := 'drop restore point '||rec.name;
        dbms_output.put_line('STEP $STEP: INFO - '||l_sql);
        execute immediate l_sql;
      end loop;
    end;
    /
    spool off
    exit
EOF

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to drop restore point in primary database ${TARGET_DBUNNAME}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully dropped restore point in primary database ${TARGET_DBUNNAME}"
    fi
  fi
  next_step
}

show_broker_config ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Show broker configuration                                  #
  #                                                                       #
  #########################################################################

  PRIMDB=$(cat ${WORKDIR}/PRIMDB.lst)
  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ ${PRIMDB} != "" ]];
  then
    LogMsg "STEP $STEP: Show broker configuration"
    setenv

    dgmgrl -silent / "show configuration verbose;"

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to show dataguard configuration. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully listed dataguard configuration"
    fi;

    LogMsg "STEP $STEP: Show configuration for database ${PRIMDB}"
    dgmgrl -silent / "show database verbose \"${PRIMDB}\";"

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to show dataguard configuration for database ${PRIMDB}. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully listed dataguard configuration for database ${PRIMDB}"
    fi
  else
    LogMsg "STEP $STEP: INFO - Skipping step $STEP. No DataGuard setup available."
  fi

  if [[ $STBYDB != "" ]];
  then
    for SDB in $STBYDB
    do
     LogMsg "STEP $STEP: Show configuration for standby database ${SDB}"
     setenv

     dgmgrl -silent / "show database verbose \"${SDB}\";"

      RC=$?
      LogMsg "STEP $STEP: INFO - Exit code is $RC"
      if [ ${RC} -ne 0 ];
      then
        LogMsg "STEP $STEP: FATAL - Unable to show dataguard configuration for standby database ${SDB}. Exiting !!!"
        exit 1;
      else
        LogMsg "STEP $STEP: INFO - Successfully listed dataguard configuration for standby database ${SDB}"
      fi
    done
  fi
  next_step
}

zip_logdir ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Zip logfile directory for upload to ServiceNow             #
  #                                                                       #
  #########################################################################

  LogMsg "STEP $STEP: Zip logfile directory for upload to ServiceNow"

  ZIPFILE=${WORKDIR}/drop_restore_point_${TARGET_DBNAME}_${LogTimestamp}.zip
  zip -q -r ${ZIPFILE} ${WORKDIR} -x\*.zip

  RC=$?
  LogMsg "STEP $STEP: INFO - Exit code is $RC"
  if [ ${RC} -ne 0 ];
  then
    LogMsg "STEP $STEP: FATAL - Error zipping logfile directory for upload to ServiceNow. Exiting !!!"
    exit 1;
  else
    LogMsg "STEP $STEP: INFO - Successfully zipped logfile directory for upload to ServiceNow"
    LogMsg "STEP $STEP: INFO - Zipfile name is ${ZIPFILE}"
  fi
  next_step
}

##########
## Main ##
##########

LogMsg "Prepare database downgrade for database ${TARGET_DBNAME}"

clear
set_vars
show_params
cwd
if [ $STEP -eq 1 ];  then determine_dbtype; fi;
if [ $STEP -eq 2 ];  then stop_apply_stby; fi;
if [ $STEP -eq 3 ];  then disable_and_stop_cldb; fi;
if [ $STEP -eq 4 ];  then start_db_mount; fi;
if [ $STEP -eq 5 ];  then drop_restore_point_stby; fi;
if [ $STEP -eq 6 ];  then shutdown_stby_db; fi;
if [ $STEP -eq 7 ];  then enable_and_start_cldb; fi;
if [ $STEP -eq 8 ];  then drop_restore_point_primary; fi;
if [ $STEP -eq 9 ];  then show_broker_config; fi;
if [ $STEP -eq 10 ]; then zip_logdir; fi;
