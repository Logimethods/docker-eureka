#!/bin/bash
if [ -n "${DEBUG}" ]; then
  echo "DEBUG MODE, no exit on exception"
else
  set -e
fi

source /eureka_utils.sh
# source /eureka_utils_extended.sh

include /entrypoint_insert.sh

### EXEC CMD ###
( cmdpid=$BASHPID ;
  desable_availability &
  setup_local_containers ;
  initial_check $cmdpid ;
  (infinite_setup_check $cmdpid) &
  infinite_monitor $cmdpid ;
  include /entrypoint_prepare.sh ;
  enable_availability &
  exec "$@" 2>&1 )
