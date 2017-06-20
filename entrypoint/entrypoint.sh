#!/bin/bash
set -e

source /eureka_utils.sh

### EXEC CMD ###
( cmdpid=$BASHPID ;
  setup_local_containers ;
  initial_check $cmdpid ;
  (infinite_setup_check $cmdpid) &
  infinite_monitor $cmdpid ;
  exec "$@" 2>&1 )
