#!/bin/bash
set -e

source /eureka_utils.sh

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106

EUREKA_URL_INTERNAL=${EUREKA_URL}
: ${EUREKA_URL_INTERNAL:=eureka}
: ${EUREKA_PORT:=5000}

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

: ${CHECK_DEPENDENCIES_INTERVAL:=2}
: ${CHECK_KILL_DELAY:=5}

# Interval between checks if the process is still alive.
declare -i interval=CHECK_DEPENDENCIES_INTERVAL
# Delay between posting the SIGTERM signal and destroying the process by SIGKILL.
declare -i delay=CHECK_KILL_DELAY

#### Continuous Checks ####

if [ ${FAILED_WHEN} ]; then
  declare READINESS=true
else
  declare READINESS="null"
fi

: ${READY_WHEN:=""}
if [ ${READY_WHEN} ]; then
  declare ready=false
  desable_ping
else
  declare ready=$READINESS
fi

### EXEC CMD ###
( cmdpid=$BASHPID;
  setup_local_containers ;
  initial_check $cmdpid ;
  (infinite_setup_check $cmdpid) &
  exec "$@" 2>&1 | while read line; do >&1 echo "${EUREKA_LINE_START}${line}"; monitor_output "$line" $cmdpid ; done )
