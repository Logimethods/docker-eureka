#!/bin/bash

## MIT License
##
## Copyright (c) 2017 Logimethods
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.

### PARAMETERS
## EUREKA_LINE_START
## EUREKA_PROMPT
## EUREKA_AVAILABILITY_PORT
## DEPENDS_ON
## DEPENDS_ON_SERVICES
## WAIT_FOR
## READY_WHEN
## FAILED_WHEN
## NODE_ID
## SETUP_LOCAL_CONTAINERS
## EUREKA_URL
## CHECK_TIMEOUT

# https://stackoverflow.com/questions/39162846/what-does-set-e-and-set-a-do-in-bash-what-are-other-options-that-i-can-use-wit
if [ -n "${EUREKA_DEBUG}" ]; then
  echo "EUREKA_DEBUG MODE, no exit on exception"
else
  set -e
fi

source ./eureka_utils.sh
# source /eureka_utils_extended.sh

set -a

### EXEC CMD ###
( cmdpid=$BASHPID ;
  include /entrypoint_insert.sh ;
  run_tasks 'INIT'
#  desable_availability ;
#  setup_local_containers ;
#  initial_check $cmdpid ;
  (run_tasks "CONTINUOUS_CHECK_INIT#$cmdpid") &
#  (infinite_setup_check $cmdpid) &
#  infinite_monitor $cmdpid ;
  include /entrypoint_prepare.sh ;
  if [ -z "${READY_WHEN}" ]; then
    enable_availability;
  fi ;

  if [ -n "${READY_WHEN}" ] || [ -n "${FAILED_WHEN}" ]; then
    log 'info' "Ready/Failed Monitoring Started"
    ## https://stackoverflow.com/questions/4331309/shellscript-to-monitor-a-log-file-if-keyword-triggers-then-execute-a-command
    exec "$@" | \
      while read line ; do
    #    >&2 echo "${EUREKA_LINE_START}${line}"
        echo "${EUREKA_LINE_START}${line}"
        monitor_output "$line" $cmdpid
      done
  else
    log 'info' "Started without Monitoring"
    exec "$@"
  fi
)

if [[ $EUREKA_DEBUG = *stay* ]]; then
  log 'info' "STAY FOREVER!!!"
  while true; do sleep 100000 ; done
fi
