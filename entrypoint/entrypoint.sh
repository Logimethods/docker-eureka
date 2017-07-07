#!/bin/bash
set -e

source /eureka_utils.sh

include /entrypoint_insert.sh

### EXEC CMD ###
( cmdpid=$BASHPID ;
  desable_ping &
  setup_local_containers ;
  initial_check $cmdpid ;
  (infinite_setup_check $cmdpid) &
  infinite_monitor $cmdpid ;
  include /entrypoint_prepare.sh ;
  enable_ping &
  setup_availability
  exec "$@" 2>&1 )
