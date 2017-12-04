#!/bin/bash

EUREKA_DEBUG="XXXX_tasks_info_OOOO"
EUREKA_PROMPT="~~~"

declare __RUNNING=true
declare -a __TASKS

log() {
  if [[ $EUREKA_DEBUG = *$1* ]]; then
    echo "${EUREKA_PROMPT}$2"
  fi
}

add_tasks() {
  __NEW_TASKS+=($@)
  log "tasks" "++ <${__NEW_TASKS[*]}>"
}

stop_tasks() {
  __RUNNING=false
}

remove_tasks() {
  delete=($@)
  ## https://stackoverflow.com/questions/16860877/remove-element-from-array-shell
  for target in "${delete[@]}"; do
    for i in "${!__NEW_TASKS[@]}"; do
      if [[ ${__NEW_TASKS[i]} = "${target}" ]]; then
        unset '__NEW_TASKS[i]'
      fi
    done
  done
  log "tasks"  "-- <${__NEW_TASKS[*]}>"
}

run_tasks() {
  __TASKS+=($@)

  while $__RUNNING && [[ ${#__TASKS[@]} -ne 0 ]]; do
#    log "tasks" "[${__TASKS[*]}]"
    log "info" "[${__TASKS[*]}]"
#    echo "---"
#    printf '%s, ' "${__TASKS[@]}"
#    echo "---"
##-    log "tasks"  "=${__TASKS[0]}"

    __NEW_TASKS=()
    for __TASK in "${__TASKS[@]}"; do
      command=$(echo $__TASK | tr '#' ' ')
      log info "\$ $command"
      eval $command
#      eval $(echo $__TASK | tr '#' ' ')
#      $__TASK
    done

    log "tasks" "__NEW_TASKS: [${__NEW_TASKS[*]}]"
    ## https://stackoverflow.com/questions/13648410/how-can-i-get-unique-values-from-an-array-in-bash
    __TASKS=($(tr ' ' '\n' <<<"${__NEW_TASKS[@]}" | awk '!u[$0]++' | tr '\n' ' '))
    ##__TASKS=($(echo "${__NEW_TASKS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  done
}

INIT() {
  echo ">INIT"
  add_tasks 'MIDDLE' 'REMOVE'
#  __RUNNING=false
  add_tasks 'MIDDLE' 'MIDDLE' 'ADD#END'

#  __CHECK_TIMEOUT=`echo $(date +%s) + $CHECK_TIMEOUT | bc`
  add_tasks "CHECK_TIMEOUT"
}

MIDDLE() {
  echo ">MIDDLE"
  add_tasks 'NOP' 'KO' 'KO2' 'KO'
}

REMOVE() {
  echo ">REMOVE"
  remove_tasks 'KO2' 'KO'
}

NOP() {
  echo ">NOP"
}

ADD() {
  echo ">ADD $1"
  add_tasks "$1"
}

END() {
  echo ">END"
#  __RUNNING=false
}

CHECK_TIMEOUT() {
  if [[ $__TASKS != 'CHECK_TIMEOUT' ]]; then
    __date=$(date +%s)
    echo "$__date"
    if [[ $__CHECK_TIMEOUT -gt $__date ]]; then
      add_tasks 'CHECK_TIMEOUT'
    else
      stop_tasks
    fi
  fi
}

run_tasks 'INIT'