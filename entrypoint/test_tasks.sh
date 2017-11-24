#!/bin/bash

EUREKA_DEBUG="info"
EUREKA_PROMPT="~ "
CHECK_TIMEOUT=2

source ./eureka_utils.sh

XINIT() {
  echo ">XINIT"

  __CHECK_TIMEOUT=`echo $(date +%s) + $CHECK_TIMEOUT | bc`
  add_tasks "CHECK_TIMEOUT"

  add_tasks 'MIDDLE' 'REMOVE'
#  __RUNNING=false
  add_tasks 'MIDDLE' 'MIDDLE' 'ADD#END'
}

MIDDLE() {
  echo ">MIDDLE"
  add_tasks 'NOP' 'KO' 'KO2' 'KO'
  add_tasks 'INFINITE'
}

REMOVE() {
  echo ">REMOVE"
  remove_tasks 'KO2' 'KO'
}

INFINITE() {
  echo ">INFINITE"
  add_tasks 'INFINITE'
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

run_tasks 'XINIT'