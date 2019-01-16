#!/bin/sh
# Script        : enable_dataguard.sh
# Purpose       : see usage
# Usage         : see usage
# ***************************************************************************************************************
# * Date        Version Name      Change                                                                    *
# * -----------  -----  ---------- ---------------------------------------------------------------------------- *
# * 2016/06/01   1.00   Monowar Mukul  Initial TEST version                                                       *
# ***************************************************************************************************************

#set -vx

usage () {

echo "

Purpose       : $0
                upgrade a database to version 12c.

Prerequisite  : Databases must be running

Usage         : $0 [-h|-d|-s|-e]

Flags         : -d database name of the database to upgrade
                -s step to start with (optional)
                -e step to end with (optional)
                -h help

Examples      : $0 -d ADBA1 (all upgrade steps will be executed)
                $0 -d ADBA1 -s 5 (all upgrade steps starting with step 5 will be executed)
                $0 -d ADBA1 5 -e 7 (all upgrade steps starting with step 5 up and until step 7 will be executed)


               Show usage
               $0 -h

Script steps  : 1  : Enable dataguard configuration
                2  : Enable standby databases
                3  : Start apply on standby database
                4  : Enable transport for DataGuard setup
                5  : Set broker protection level to MaxAvailability
                6  : Show broker configuration
                7  : Zip logfile directory for upload to ServiceNow

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
  ORATAB=/etc/oratab
  if [ -z "${TARGET_SID}" ];
  then
    TARGET_SID=$(ps -ef|grep pm[o]n|grep ${TARGET_DBNAME}|grep -v tfa|awk '{print substr($NF,10)}')
  fi
  CLUSTER=$($GIHOME/bin/olsnodes -c)
  LogTimestamp=$(date +%Y%m%d_%H%M%S)
  WORKDIR=/iorsdb_apac_migration/12cUPGRADE/${TARGET_DBNAME}
  LOGFILE=${WORKDIR}/enable_dataguard_${TARGET_DBNAME}_${LogTimestamp}.log
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
  LogMsg "The following paramaters are provided and will be used to upgrade the standby database"
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

next_step ()
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

enable_dg_config ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Enable dataguard configuration                             #
  #                                                                       #
  #########################################################################

  PRIMDB=$(cat ${WORKDIR}/PRIMDB.lst)

  if [[ $PRIMDB != "" ]];
  then
    LogMsg "STEP $STEP: Enable dataguard configuration"
    setenv

    dgmgrl -silent / "enable configuration;"

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to enable dataguard configuration. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully enabled dataguard configuration"
    fi
  else
    LogMsg "STEP $STEP: INFO - No dataguard setup available. Exiting !!!"
    exit 1
  fi
  next_step
}

enable_stby_config ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Enable standby databases                                   #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    for DB in $STBYDB
    do
     LogMsg "STEP $STEP: Enable standby database ${STBYDB}"
     setenv

     dgmgrl -silent / "enable database \"${STBYDB}\";"

      RC=$?
      LogMsg "STEP $STEP: INFO - Exit code is $RC"
      if [ ${RC} -ne 0 ];
      then
        LogMsg "STEP $STEP: FATAL - Unable to enable standby database ${STBYDB}. Exiting !!!"
        exit 1;
      else
        LogMsg "STEP $STEP: INFO - Successfully enabled standby database ${STBYDB}"
      fi
    done
  fi
  next_step
}

start_apply ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Start apply on standby database                            #
  #                                                                       #
  #########################################################################

  STBYDB=$(cat ${WORKDIR}/STBYDB.lst)

  if [[ $STBYDB != "" ]];
  then
    for DB in $STBYDB
    do
      LogMsg "STEP $STEP: Enable apply on standby database ${STBYDB}"
      setenv

      dgmgrl -silent / "edit database \"${STBYDB}\" set state=APPLY-ON;"

      RC=$?
      LogMsg "STEP $STEP: INFO - Exit code is $RC"
      if [ ${RC} -ne 0 ];
      then
        LogMsg "STEP $STEP: FATAL - Unable to enable apply on standby database ${STBYDB}. Exiting !!!"
        exit 1;
      else
        LogMsg "STEP $STEP: INFO - Enabled apply on standby database ${STBYDB}"
      fi
    done
  fi
  next_step
}

enable_transport ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Enable transport for DataGuard setup                       #
  #                                                                       #
  #########################################################################

  PRIMDB=$(cat ${WORKDIR}/PRIMDB.lst)

  if [[ ${PRIMDB} != "" ]];
  then
    LogMsg "STEP $STEP: Enable transport on primary database"
    setenv

    dgmgrl -silent / "edit database \"${PRIMDB}\" set state=TRANSPORT-ON;"

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to enable transport on primary database. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully enable transport on primary database"
    fi;
  fi
  next_step
}

set_max_availability ()
{
  #########################################################################
  #                                                                       #
  #  Purpose : Set broker protection level to MaxAvailability             #
  #                                                                       #
  #########################################################################

  PRIMDB=$(cat ${WORKDIR}/PRIMDB.lst)

  if [[ ${PRIMDB} != "" ]];
  then
    LogMsg "STEP $STEP: Set broker protection level to MaxAvailability"
    setenv

    dgmgrl -silent / "EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability;"

    RC=$?
    LogMsg "STEP $STEP: INFO - Exit code is $RC"
    if [ ${RC} -ne 0 ];
    then
      LogMsg "STEP $STEP: FATAL - Unable to set broker protection level to MaxAvailability. Exiting !!!"
      exit 1;
    else
      LogMsg "STEP $STEP: INFO - Successfully set broker protection level to MaxAvailability"
    fi;
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
  fi

  if [[ $STBYDB != "" ]];
  then
    for SDB in $STBYDB
    do
     LogMsg "STEP $STEP: Show configuration for standby database ${SDB}"
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

  ZIPFILE=${WORKDIR}/enable_dataguard_${TARGET_DBNAME}_${LogTimestamp}.zip
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

clear
set_vars
show_params
if [ $STEP -eq 1 ];   then enable_dg_config; fi;
if [ $STEP -eq 2 ];   then enable_stby_config; fi;
if [ $STEP -eq 3 ];   then start_apply; fi;
if [ $STEP -eq 4 ];   then enable_transport; fi;
if [ $STEP -eq 5 ];   then set_max_availability; fi;
if [ $STEP -eq 6 ];   then show_broker_config; fi;
if [ $STEP -eq 7 ];   then zip_logdir; fi;
