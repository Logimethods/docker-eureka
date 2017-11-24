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

#### Commands Setup & Check ####

## TODO : Check the existence of all required commands
# nslookup
# wget or curl
# jq
# netcat / nc -h => Should not be "OpenBSD netcat (Debian patchlevel 4)", as founded in Alpine 3.5

# https://stackoverflow.com/questions/10735574/include-source-script-if-it-exists-in-bash
include () {
    #  [ -f "$1" ] && source "$1" WILL EXIT...
    if [ -f $1 ]; then
        echo "source $1"
        source $1
    fi
}

log() {
  if [[ $EUREKA_DEBUG = *$1* ]]; then
    echo "${EUREKA_PROMPT}$2"
  fi
}

declare __RUNNING=true
declare -a __TASKS

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
    log "info" "[${__TASKS[*]}]"
    __NEW_TASKS=()

    for __TASK in "${__TASKS[@]}"; do
      command=$(echo $__TASK | tr '#' ' ')
      log info "\$ $command"
      eval $command
    done

    log "tasks" "__NEW_TASKS: [${__NEW_TASKS[*]}]"
    ## https://stackoverflow.com/questions/13648410/how-can-i-get-unique-values-from-an-array-in-bash
    __TASKS=($(tr ' ' '\n' <<<"${__NEW_TASKS[@]}" | awk '!u[$0]++' | tr '\n' ' '))
  done
}

INIT() {
  include ./entrypoint_insert.sh ;

  if [ -n "${WAIT_FOR}" ] || [ -n "${DEPENDS_ON}" ] || [ -n "${DEPENDS_ON_SERVICES}" ]|| [ -n "${READY_WHEN}" ]; then
    add_tasks 'desable_availability'
  fi

  if [ -n "${NODE_ID}" ] || [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ]; then
    add_tasks 'setup_local_containers'
  fi

  add_tasks 'INITIAL_CHECK'
}

INITIAL_CHECK() {
  #### SETUP timeout
  if [ -n "${CHECK_TIMEOUT}" ]; then
    __CHECK_TIMEOUT=`echo $(date +%s) + $CHECK_TIMEOUT | bc`
    add_tasks "CHECK_TIMEOUT"
  fi

  if [ -n "${DEPENDS_ON_SERVICES}" ]; then
    add_tasks 'DEPENDS_ON_SERVICES_CHECK'
  fi

  if [ -n "${DEPENDS_ON}" ]; then
    __DEPENDS_ON_URLS=$(echo $DEPENDS_ON | tr "," "\n")
    add_tasks 'DEPENDS_ON_CHECK'
  fi
}

CHECK_TIMEOUT() {
  if [[ $__TASKS != 'CHECK_TIMEOUT' ]]; then
    __date=$(date +%s)
    if [[ $__CHECK_TIMEOUT -gt $__date ]]; then
      add_tasks 'CHECK_TIMEOUT'
    else
      log info 'TIME OUT!'
      stop_tasks
    fi
  fi
}

DEPENDS_ON_SERVICES_CHECK() {
  if [ "$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})" != "OK" ]; then
    log 'info' "Still WAITING for Service Dependencies ${DEPENDS_ON_SERVICES}"
    add_tasks 'DEPENDS_ON_SERVICES_CHECK'
  fi
}

DEPENDS_ON_CHECK() {
  URLS=$(echo $DEPENDS_ON | tr "," "\n")
  for URL in $URLS
  do
    add_tasks "DEPENDS_ON_URL_CHECK#${URL}"
  done
}

DEPENDS_ON_URL_CHECK() {
  URL=$1
  if call_availability ${URL}; then
    log 'availability' "${URL} URL AVAILABLE"
  else
    add_tasks "DEPENDS_ON_URL_CHECK#${URL}"
    log 'availability' "Still WAITING for ${URL} AVAILABILITY"
  fi
}

WAIT_FOR_CHECK() {
  URLS=$(echo $WAIT_FOR | tr "," "\n")
  for URL in $URLS
  do
    add_tasks "WAIT_FOR_URL_CHECK#${URL}"
  done
}

WAIT_FOR_URL_CHECK() {
  URL=$1
  if [[ $URL == *":"* ]]; then # url + port
    HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
    PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
    # TODO Simplify
    if netcat -vz -q 2 -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ; [ $result -eq 0 ] ; then
      log 'availability' "${URL} URL AVAILABLE"
    else
      log 'availability' "Still WAITING for URL $HOST:$PORT"
      if [[ "${HOST}" == *_local* ]]; then
        add_tasks 'setup_local_containers'
      fi
      add_tasks "WAIT_FOR_URL_CHECK#${URL}"
    fi
  else # ping url
    if safe_ping $URL; then
      log 'availability' "${URL} URL PING AVAILABLE"
    else
      log 'availability' "Still WAITING for $URL PING"
      if [[ "${URL}" == *_local* ]]; then
        add_tasks 'setup_local_containers'
      fi
      add_tasks "WAIT_FOR_URL_CHECK#${URL}"
    fi
  fi
}

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106

function call_eureka() {
    if hash curl 2>/dev/null; then
        echo $(curl -s "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@")
    else
        echo $(wget -q -O - "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@")
    fi
}

add_dns_entry() {
  host=$1
  target=$2

  if [[ $EUREKA_DEBUG = *dns* ]]; then
    echo "${EUREKA_PROMPT}O ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    cat ~/hosts.new
    echo "${EUREKA_PROMPT}1 ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "${EUREKA_PROMPT}$host $target"
    echo "${EUREKA_PROMPT}2 ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  fi

  # https://stackoverflow.com/questions/24991136/docker-build-could-not-resolve-archive-ubuntu-com-apt-get-fails-to-install-a

  local lookup=$(nslookup ${target} 2>/dev/null)
  local ip=$(echo $lookup | grep "." | tail -n1 | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')

  # http://jasani.org/2014/11/19/docker-now-supports-adding-host-mappings/
  sed -i "/${host}\$/d" ~/hosts.new
  echo "$ip $host" >> ~/hosts.new

  if [[ $EUREKA_DEBUG = *dns* ]]; then
    echo "${EUREKA_PROMPT}A ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "${EUREKA_PROMPT}nslookup ${target} ="
    echo "${EUREKA_PROMPT}$lookup"
    echo "${EUREKA_PROMPT}B ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "${EUREKA_PROMPT}$ip $host"
    echo "${EUREKA_PROMPT}C ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    cat ~/hosts.new
    echo "${EUREKA_PROMPT}D ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  fi
}

setup_local_containers() {
##-  if [ -n "${NODE_ID}" ] || [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ]; then
    # http://blog.jonathanargentiero.com/docker-sed-cannot-rename-etcsedl8ysxl-device-or-resource-busy/
    cp /etc/hosts ~/hosts.new

    if [ -z "$NODE_ID" ]; then
      SERVICES=$(call_eureka /services)
    else
      SERVICES=$(call_eureka /services/node/${NODE_ID})
    fi

    if [[ $EUREKA_DEBUG = *services* ]]; then
      echo "${EUREKA_PROMPT}SERVICES= $SERVICES"
    fi

    # https://stedolan.github.io/jq/
    while IFS="=" read name value; do
      container="${value/%\ */}"
      export "${name//-/_}=${container}"
      add_dns_entry ${name} ${container}

      export "${name//-/_}0=\"$value\""
      i=1
      for container in $value; do
        ## Stored as an Environment Variable
        entry=${name}$((i++))
        export "${entry//-/_}=${container}"
        ## Added as a DNS entry
        add_dns_entry ${entry} ${container}
      done
    done < <( echo "$SERVICES" | jq '.[] | tostring' | sed -e 's/\"{\\\"//g' -e 's/\\\"\:\[\\\"/_local=/g' -e 's/\\\",\\\"/\\\ /g' -e 's/\\\"]}\"//g')

    # cp -f ~/hosts.new /etc/hosts # cp: can't create '/etc/hosts': File exists
    echo "$(cat ~/hosts.new)" > /etc/hosts

    if [[ $EUREKA_DEBUG = *trace* ]]; then
      echo "${EUREKA_PROMPT}$EUREKA_URL_INTERNAL:$EUREKA_PORT"
      env | grep -v _local | sort
      env | grep _local | sort
      echo "${EUREKA_PROMPT}---------"
      cat /etc/hosts
    fi
##-  fi
}

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

# https://stackoverflow.com/questions/26177059/refresh-net-core-somaxcomm-or-any-sysctl-property-for-docker-containers/26197875#26197875
# https://stackoverflow.com/questions/26050899/how-to-mount-host-volumes-into-docker-containers-in-dockerfile-during-build
# docker run ... -v /proc:/writable-proc ...
desable_availability() {
  log "ping" "desable_availability asked"

#  write_availability_file 503 "Service Unavailable" 19
  if [ -n "${available_pid}" ]; then
    kill -9 ${available_pid}
    export available_pid=0
  fi

  if [ -e /writable-proc/sys/net/ipv4/icmp_echo_ignore_all ]; then
    echo "1" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
  else
    echo "${EUREKA_PROMPT}desable ping not allowed"
  fi

  rm -f /availability.lock

  log "health" "desable_availability: $(cat /availability.lock)"
}

enable_availability() {
  if [[ $EUREKA_DEBUG = *ping* ]]; then echo "${EUREKA_PROMPT}enable_availability asked"; fi

  if [ "$AVAILABILITY_ALLOWED" != "false" ]; then
    ( while true; do echo "^C" | answer_availability ; done ) &
    export available_pid=$!
  fi

  if [ -e /writable-proc/sys/net/ipv4/icmp_echo_ignore_all ]; then
    echo "0" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
  fi

  echo "AVAILABLE" > /availability.lock
  if [[ $EUREKA_DEBUG = *health* ]]; then echo "${EUREKA_PROMPT}enable_availability: $(cat /availability.lock)"; fi
}

safe_ping() {
  if [[ $(cat /proc/sys/net/ipv4/icmp_echo_ignore_all) == "0" ]]; then
    ping -c1 "$1" &>/dev/null
    return $?
  else
    if [[ $1 =~ _local[0-9]*$ ]]; then # The urls ending with _local[0-9]* are not known by Eureka...
      local url="${!1}" # https://stackoverflow.com/questions/14049057/bash-expand-variable-in-a-variable
      if [[ $EUREKA_DEBUG = *ping* ]]; then echo "${EUREKA_PROMPT}$1 resolved as ${url}" ; fi
    else
      local url="$1"
      if [[ $EUREKA_DEBUG = *ping* ]]; then echo "${EUREKA_PROMPT}$1 applied to ${url}" ; fi
    fi
    if [[ $EUREKA_DEBUG = *ping* ]]; then echo "${EUREKA_PROMPT}\$(call_eureka /ping/$url) = $(call_eureka /ping/$url)"; fi
    test $(call_eureka /ping/$url) == "OK"
    return $?
  fi
}

kill_cmdpid () {
  if [ "$KILL_WHEN_FAILED" = "true" ]; then
    declare cmdpid=$1
    # http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
    # Be nice, post SIGTERM first.
    # The 'exit 0' below will be executed if any preceeding command fails.
    kill -s SIGTERM $cmdpid && kill -0 $cmdpid || exit 0
    sleep $delay
    kill -s SIGKILL $cmdpid
  else
    ready=false
    desable_availability &
  fi
}

#### AVAILABILITY ###

## https://www.computerhope.com/unix/nc.htm
function call_availability() {
  if [[ $EUREKA_DEBUG = *netcat* ]]; then
    echo "netcat -z -q 2 $1 ${EUREKA_AVAILABILITY_PORT}"
  fi
  netcat -z -q 2 $1 ${EUREKA_AVAILABILITY_PORT}
}

if ! hash netcat  2>/dev/null && [[ ! -f /usr/bin/netcat ]]; then ln -s $(which nc) /usr/bin/netcat; fi
if [[ $EUREKA_DEBUG = *netcat* ]]; then
  netcat -h
fi

answer_availability() {
  if [[ $EUREKA_DEBUG = *netcat* ]]; then
    echo "netcat -lk -q 1 -p ${EUREKA_AVAILABILITY_PORT}"
  fi
  netcat -lk -q 1 -p "${EUREKA_AVAILABILITY_PORT}"
}

#### Initial Checks ####

___initial_check() {
  declare cmdpid=$1

  #### SETUP timeout
  if [ -n "${CHECK_TIMEOUT}" ]; then
    add_tasks "CHECK_TIMEOUT"
    __CHECK_TIMEOUT=`echo $(date +%s) + $CHECK_TIMEOUT | bc`
  fi

  # https://docs.docker.com/compose/startup-order/
  if [ -n "${DEPENDS_ON_SERVICES}" ]; then
    >&2 echo "${EUREKA_PROMPT}Checking SERVICE DEPENDENCIES ${DEPENDS_ON_SERVICES}"
    until [ "$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})" == "OK" ]; do
      >&2 echo "${EUREKA_PROMPT}Still WAITING for Service Dependencies ${DEPENDS_ON_SERVICES}"
      sleep $interval
    done
  fi

  if [ -n "${DEPENDS_ON}" ]; then
    >&2 echo "${EUREKA_PROMPT}Checking DEPENDENCIES ${DEPENDS_ON}"
    URLS=$(echo $DEPENDS_ON | tr "," "\n")
    for URL in $URLS
    do
      if [[ $EUREKA_DEBUG = *availability* ]]; then
        echo "${EUREKA_PROMPT}\$(call_availability ${URL}) = $(call_availability ${URL} 2>&1 ; echo $?)"
      fi
      until call_availability ${URL}; do
        >&2 echo "${EUREKA_PROMPT}Still WAITING for Dependencies ${URL}"
        if [[ $EUREKA_DEBUG = *availability* ]]; then
          echo "${EUREKA_PROMPT}\$(call_availability ${URL}) = $(call_availability ${URL} 2>&1 ; echo $?)"
        fi
        if [[ "${URL}" == *_local* ]]; then
          setup_local_containers
        fi
        sleep $interval
      done
    done
  fi

  # https://github.com/Eficode/wait-for
  if [ -n "${WAIT_FOR}" ]; then
    >&2 echo "${EUREKA_PROMPT}Checking URLS $WAIT_FOR"
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      if [[ $URL == *":"* ]]; then # url + port
        HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
        PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
        # TODO Simplify
        until netcat -vz -q 2 -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ; [ $result -eq 0 ] ; do
          >&2 echo "${EUREKA_PROMPT}Still WAITING for URL $HOST:$PORT"
          if [[ "${HOST}" == *_local* ]]; then
            setup_local_containers
          fi
          sleep $interval
        done
      else # ping url
        until safe_ping $URL; do
          >&2 echo "Still WAITING for $URL PING"
          if [[ "${URL}" == *_local* ]]; then
            setup_local_containers
          fi
          sleep $interval
        done
      fi
    done
  fi

  # Kill the CHECK_TIMEOUT loop if still alive
  if [ -n "${CHECK_TIMEOUT}" ]; then
    echo "${EUREKA_PROMPT}KILL KILL! $timeout_pid / $cmdpid"
    kill $timeout_pid
  fi
}

#### Continuous Checks ####

check_dependencies(){
  declare cmdpid=$1

  if [ -n "${DEPENDS_ON_SERVICES}" ]; then
    dependencies_checked=$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})
    if [ "$dependencies_checked" != "OK" ]; then
      >&2 echo "${EUREKA_PROMPT}Failed Check Services Dependencies ${DEPENDS_ON_SERVICES}"
      kill_cmdpid $cmdpid
    fi
  fi

  if [ -n "${DEPENDS_ON}" ]; then
    URLS=$(echo $DEPENDS_ON | tr "," "\n")
    for URL in $URLS
    do
      if ! call_availability ${URL}; then
        >&2 echo "${EUREKA_PROMPT}Failed ${URL} Availability"
        kill_cmdpid $cmdpid
      fi
    done
  fi

  # https://github.com/Eficode/wait-for
  if [ -n "${WAIT_FOR}" ]; then
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      if [[ $URL == *":"* ]]; then # url + port
        HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
        PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
        # TODO Simplify
        netcat -z -q 2 "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ;
        if [ $result -ne 0 ] ; then
          >&2 echo "${EUREKA_PROMPT}Failed Check URL ${URL}"
          if [ "$KILL_WHEN_FAILED" = "true" ]; then
            kill_cmdpid $cmdpid
          fi
        fi
      elif ! safe_ping $URL ; then # ping url
        >&2 echo "${EUREKA_PROMPT}Failed ${URL} Ping"
        kill_cmdpid $cmdpid
      fi
    done
  fi
}

infinite_setup_check(){
  if [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ] || [ -n "${DEPENDS_ON}" ] || [ -n "${WAIT_FOR}" ]; then
    while true
    do
      setup_local_containers
      sleep $interval
      if [ "$CONTINUOUS_CHECK" == "true" ] ; then
        check_dependencies $1
      fi
    done
  fi
}

infinite_monitor(){
  if [[ $EUREKA_DEBUG = *monitor* ]]; then
    >&2 echo "${EUREKA_PROMPT}infinite_monitor ASKED";
    env
  fi

  if [ -n "${READY_WHEN}" ] || [ -n "${FAILED_WHEN}" ]; then
    exec 1> >(
    while read line
    do
      >&2 echo "${EUREKA_LINE_START}${line}"
      monitor_output "$line" $1
    done
    )

    if [[ $EUREKA_DEBUG = *monitor* ]]; then
      >&2 echo "${EUREKA_PROMPT}infinite_monitor STARTED";
    fi
  fi
}

monitor_output() {
  declare cmdpid=$2

  if [[ $EUREKA_DEBUG = *tracemonitor* ]]; then
    >&2 echo "${EUREKA_PROMPT}Monitor: ready=${ready}, input='${1}'";
  fi

  if [ "$ready" = false ] && [[ $1 == *"${READY_WHEN}"* ]]; then
    # TODO Only once!!!
    >&2 echo "${EUREKA_PROMPT}FINALIZE!"

    ## Optional finalizing
    include entrypoint_finalize.sh

    >&2 echo "${EUREKA_PROMPT}READY!"

    ready="$READINESS"
    enable_availability &
  fi
  if [ "$ready" = true ] && [[ $1 == *"${FAILED_WHEN}"* ]]; then
    >&2 echo "${EUREKA_PROMPT}FAILED!"
    kill_cmdpid $cmdpid
  fi
}

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106

EUREKA_URL_INTERNAL=${EUREKA_URL}
: ${EUREKA_URL_INTERNAL:=eureka}
: ${EUREKA_PORT:=5000}
: ${EUREKA_PROMPT:=EUReKA: }

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

: ${EUREKA_AVAILABILITY_PORT:=6868}
: ${CHECK_DEPENDENCIES_INTERVAL:=2}
: ${CHECK_KILL_DELAY:=5}
: ${CONTINUOUS_CHECK:=false}

# Interval between checks if the process is still alive.
declare -i interval=CHECK_DEPENDENCIES_INTERVAL
# Delay between posting the SIGTERM signal and destroying the process by SIGKILL.
declare -i delay=CHECK_KILL_DELAY

#### Continuous Checks ####

if [ -n "${FAILED_WHEN}" ]; then
  declare READINESS=true
else
  declare READINESS="null"
fi

if [ -n "${READY_WHEN}" ]; then
  declare ready=false
  desable_availability
else
  declare ready=$READINESS
fi
