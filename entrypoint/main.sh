#!/bin/bash

__RUNNING=true
__TASKS=()

add_tasks() {
  __NEW_TASKS+=($@)
  echo "<${__NEW_TASKS[*]}>"
}

run_taks() {
  __TASKS+=($@)

  while $__RUNNING && [[ ${#__TASKS[@]} -ne 0 ]]; do
    echo "[${__TASKS[*]}]"
    __NEW_TASKS=()
    for __TASK in $__TASKS; do
      '__'$__TASK
    done
    echo "__NEW_TASKS: [${__NEW_TASKS[*]}]"
    ## https://stackoverflow.com/questions/13648410/how-can-i-get-unique-values-from-an-array-in-bash
    __TASKS=($(tr ' ' '\n' <<<"${__NEW_TASKS[@]}" | awk '!u[$0]++' | tr '\n' ' '))
    ##__TASKS=($(echo "${__NEW_TASKS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  done
}

__INIT() {
  echo ">INIT"
  add_tasks 'MIDDLE'
#  __RUNNING=false
  add_tasks 'MIDDLE' 'MIDDLE' 'END'
}

__MIDDLE() {
  echo ">MIDDLE"
  add_tasks 'NOP'
}

__NOP() {
  echo ">NOP"
}

__END() {
  echo ">END"
#  __RUNNING=false
}

run_taks 'INIT'