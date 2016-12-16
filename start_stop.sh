#!/usr/bin/ksh

export LOGFILE="logs/start_stop-`date +%d%m%Y_%H.%M`.log"


main() {
case "$1" in
  start)
        {
        date
        action_listeners start
        action_databases start
  #     start_agent
        date
        } 2>&1 | tee -a $LOGFILE
  ;;
  stop)
        {
        date
  #     stop_agent
        action_listeners stop
        action_databases stop
        date
        } 2>&1 | tee -a $LOGFILE
  ;;
  *)
  echo $"Usage: $0 start|stop"
  exit 0
esac
}

eho1() {
BBlack='\e[1;30m'       # Black
BRed='\e[1;31m'         # Red
BGreen='\e[1;32m'       # Green
BYellow='\e[1;33m'      # Yellow
BBlue='\e[1;34m'        # Blue
BPurple='\e[1;35m'      # Purple
BCyan='\e[1;36m'        # Cyan
BWhite='\e[1;37m'       # White
Color_Off='\e[0m'       # Text Reset
printf "${BPurple}${1}${Color_Off}\n"
}

set_env() {
export ORACLE_SID="$1"
ORAENV_ASK="NO"
. oraenv >/dev/null 2>&1
}

parse_oratab_dbs() {
if [ `uname` == 'SunOS' ];
then
ORATAB=/var/opt/oracle/oratab
else
ORATAB=/etc/oratab
fi
for a in `grep -E '^[a-zA-Z0-9]+:[a-zA-Z0-9\/]+:Y' $ORATAB`;
do
sid=`echo $a | awk -F : {'print $1'}`
echo $sid
done
}

parse_oratab_homes() {
if [ `uname` == 'SunOS' ];
then
ORATAB=/var/opt/oracle/oratab
else
ORATAB=/etc/oratab
fi
grep -E '^[a-zA-Z0-9]+:[a-zA-Z0-9\/]+:Y' $ORATAB | awk -F : {'print $2'} | uniq
}

parse_listener_ora() {
# cat $1/listener.ora \
# | grep -Eo '^[a-zA-Z0-9_]+' \
cat $1 \
 | perl -l -ne '/^([a-zA-Z0-9_])+/ && print $&' \
 | grep -Ev '(SID_LIST|SECURE_CONTROL|SECURE_REGISTER|SECURE_PROTOCOL|DYNAMIC_REGISTRATION)' \
 | grep -Ev '(CONNECTION_RATE|ADMIN_RESTRICTIONS|CRS_NOTIFICATION|DEFAULT_SERVICE|SUBSCRIBE_FOR_NODE_DOWN_EVENT)' \
 | grep -Ev '(INBOUND_CONNECT_TIMEOUT|PASSWORDS|SAVE_CONFIG_ON_STOP|SSL_CLIENT_AUTHENTICATION)' \
 | grep -Ev '(STARTUP_WAIT_TIME|SUBSCRIBE_NODE_DOWN_EVENT|WALLET_LOCATION|ADR_BASE|DIAG_ADR_ENABLED)' \
 | grep -Ev '(LOGGING|TRACE_LEVEL|TRACE_TIMESTAMP|LOG_DIRECTORY|LOG_FILE|TRACE_DIRECTORY)' \
 | grep -Ev '(TRACE_FILELEN|TRACE_FILENO|SECURE_CONTROL|SECURE_REGISTER|SECURE_PROTOCOL|DYNAMIC_REGISTRATION)'
}

action_listeners() {
for OHOME in `parse_oratab_homes`; do
 export ORACLE_HOME=${OHOME}
 export PATH=${ORACLE_HOME}/bin:$PATH
 export LD_LIBRARY_PATH=${ORACLE_HOME}/lib
 LISTENER_ORA=$ORACLE_HOME/network/admin/listener.ora
 if [ -f $LISTENER_ORA ];
 then
 for a in `parse_listener_ora ${LISTENER_ORA}`; do
 if [ "$1" == "start" ];
 then
 start_listener $a
 elif [ "$1" == "stop" ]; then
 stop_listener $a
 else
 echo "Unknown action $1"
 exit 1
 fi
 done
 fi
done
}

action_databases() {
for a in `parse_oratab_dbs`; do
if [ "$1" == "start" ];
then
  set_env $a
  start_database $a
elif [ "$1" == "stop" ]; then
  set_env $a
  shutdown_database $a
else
  echo "Unknown action $1"
  exit 1
fi
done
}

start_listener() {
eho1 "Starting Oracle Listener $1 using binaries $ORACLE_HOME"
echo "---------------------------------------------------------------"
lsnrctl start $1
echo "---------------------------------------------------------------"
}

stop_listener() {
eho1 "Stopping Oracle Listener $1"
echo "---------------------------------------------------------------"
lsnrctl stop $1
echo "---------------------------------------------------------------"
}

start_database() {
eho1 "Starting Oracle Instance $1"
echo "---------------------------------------------------------------"
sqlplus /nolog <<EOF
connect / as sysdba
startup mount;
exit
EOF

DBROLE=`sqlplus -silent / as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT database_role from v\\$database;
EXIT;
EOF`

if [ "$DBROLE" = "PRIMARY" ];
then
sqlplus /nolog <<EOF
connect / as sysdba
alter system set log_archive_dest_state_2=enable;
alter database open;
exit
EOF
else
sqlplus /nolog <<EOF
connect / as sysdba
recover managed standby database using current logfile disconnect;
exit
EOF
fi

echo "---------------------------------------------------------------"
}

shutdown_database() {
eho1 "Shutting down database $1"
echo "---------------------------------------------------------------"
sqlplus /nolog <<EOF
connect / as sysdba
shutdown immediate;
exit
EOF
echo "---------------------------------------------------------------"
}

start_agent() {
eho1 "Starting OEM AGENT"
echo "---------------------------------------------------------------"
export ORACLE_SID="AGENT12C"
ORAENV_ASK="NO"
. oraenv >/dev/null 2>&1
emctl start agent
emctl stop blackout bl_$(hostname -s)
emctl status agent
echo "---------------------------------------------------------------"
}

stop_agent() {
eho1 "Stopping OEM AGENT"
echo "---------------------------------------------------------------"
export ORACLE_SID="AGENT12C"
ORAENV_ASK="NO"
. oraenv >/dev/null 2>&1
emctl start blackout bl_$(hostname -s) -nodeLevel
emctl stop agent
emctl status agent
echo "---------------------------------------------------------------"
}

main $1
unset LOGFILE
