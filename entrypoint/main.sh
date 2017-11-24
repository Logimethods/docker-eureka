#!/bin/bash

EUREKA_DEBUG="XXXX_tasks_OOOO"
EUREKA_PROMPT="~~~"

__RUNNING=true
__TASKS=()

log() {
  if [[ $EUREKA_DEBUG = *$1* ]]; then
    echo "${EUREKA_PROMPT}$2"
  fi
}

add_tasks() {
  __NEW_TASKS+=($@)
  log "tasks" "++ <${__NEW_TASKS[*]}>"
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

run_taks() {
  __TASKS+=($@)

  while $__RUNNING && [[ ${#__TASKS[@]} -ne 0 ]]; do
    log "tasks" "[${__TASKS[@]}]"
    log "info" "[${__TASKS[@]}]"
##-    log "tasks"  "=${__TASKS[0]}"
    __NEW_TASKS=()
    for __TASK in "${__TASKS[@]}"; do
      $__TASK
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
  add_tasks 'MIDDLE' 'MIDDLE' 'END'
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

__END() {
  echo ">END"
#  __RUNNING=false
}

run_taks 'INIT'