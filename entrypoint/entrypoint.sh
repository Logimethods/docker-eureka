#!/bin/bash
set -e

source /eureka_utils.sh

include /entrypoint_insert.sh

### EXEC CMD ###
( cmdpid=$BASHPID ;
  setup_local_containers ;
  initial_check $cmdpid ;
  (infinite_setup_check $cmdpid) &
  infinite_monitor $cmdpid ;
  include /entrypoint_prepare.sh ;
  exec "$@" 2>&1 )
