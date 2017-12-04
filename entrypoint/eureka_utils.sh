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
      if $__RUNNING ; then
        command=$(echo $__TASK | tr '#' ' ')
        log info "\$ $command"
        eval $command
      fi
    done

    log "tasks" "__NEW_TASKS: [${__NEW_TASKS[*]}]"
    ## https://stackoverflow.com/questions/13648410/how-can-i-get-unique-values-from-an-array-in-bash
    __TASKS=($(tr ' ' '\n' <<<"${__NEW_TASKS[@]}" | awk '!u[$0]++' | tr '\n' ' '))
  done
}

INIT() {
  include ./entrypoint_insert.sh ;

  if [ -n "${WAIT_FOR}" ] || [ -n "${DEPENDS_ON}" ] || [ -n "${DEPENDS_ON_SERVICES}" ]|| [ -n "${READY_WHEN}" ]; then
    add_tasks 'disable_availability'
  fi

  if [ -n "${NODE_ID}" ] || [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ]; then
    add_tasks 'setup_local_containers'
  fi

  add_tasks 'INITIAL_WAIT'
}

INITIAL_WAIT() {
  #### SETUP timeout
  if [ -n "${CHECK_TIMEOUT}" ]; then
    __WAIT_TIMEOUT=`echo $(date +%s) + $CHECK_TIMEOUT | bc`
    log 'info' "TIMEOUT SET to $CHECK_TIMEOUT seconds"
    add_tasks "WAIT_TIMEOUT"
  fi

  if [ -n "${DEPENDS_ON_SERVICES}" ]; then
    add_tasks 'DEPENDS_ON_SERVICES_WAIT'
  fi

  if [ -n "${DEPENDS_ON}" ]; then
    URLS=$(echo $DEPENDS_ON | tr "," "\n")
    for URL in $URLS
    do
      add_tasks "DEPENDS_ON_URL_WAIT#${URL}"
    done
  fi

  # https://github.com/Eficode/wait-for
  if [ -n "${WAIT_FOR}" ]; then
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      add_tasks "WAIT_FOR_URL#${URL}"
    done
  fi
}

WAIT_TIMEOUT() {
  if [[ "${__TASKS[*]}" != 'WAIT_TIMEOUT' ]]; then
    __date=$(date +%s)
    if [[ $__WAIT_TIMEOUT -gt $__date ]]; then
      add_tasks 'WAIT_TIMEOUT'
    else
      log info 'TIME OUT!'
      stop_tasks
    fi
  fi
}

DEPENDS_ON_SERVICES_WAIT() {
  if [ "$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})" != "OK" ]; then
    log 'info' "Still WAITING for Service Dependencies ${DEPENDS_ON_SERVICES}"
    add_tasks 'DEPENDS_ON_SERVICES_WAIT'
  fi
}

SLEEP() {
  log 'sleep' "$1"
  sleep ${1}
}

DEPENDS_ON_URL_WAIT() {
  URL=$1
  if call_availability ${URL}; then
    log 'availability' "${URL} URL AVAILABLE"
  else
    add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "DEPENDS_ON_URL_WAIT#${URL}"
    log 'availability' "Still WAITING for ${URL} AVAILABILITY"
  fi
}

WAIT_FOR_URL() {
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
      add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "WAIT_FOR_URL#${URL}"
    fi
  else # ping url
    if safe_ping $URL; then
      log 'availability' "${URL} URL PING AVAILABLE"
    else
      log 'availability' "Still WAITING for $URL PING"
      if [[ "${URL}" == *_local* ]]; then
        add_tasks 'setup_local_containers'
      fi
      add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "WAIT_FOR_URL#${URL}"
    fi
  fi
}

CONTINUOUS_CHECK_INIT() {
  cmdpid=$1

  if [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ]; then
    add_tasks "CONTINUOUS_LOCAL_CONTAINERS_SETUP"
  fi

  if [ "$CONTINUOUS_CHECK" == "true" ] ; then
    if [ -n "${DEPENDS_ON_SERVICES}" ]; then
      add_tasks "CONTINUOUS_LOCAL_CONTAINERS_SETUP" "DEPENDS_ON_SERVICES_CHECK#$cmdpid"
    fi

    if [ -n "${DEPENDS_ON}" ]; then
      URLS=$(echo $DEPENDS_ON | tr "," "\n")
      for URL in $URLS
      do
        add_tasks "DEPENDS_ON_URL_CHECK#${URL}#$cmdpid"
      done
    fi

    # https://github.com/Eficode/wait-for
    if [ -n "${WAIT_FOR}" ]; then
      URLS=$(echo $WAIT_FOR | tr "," "\n")
      for URL in $URLS
      do
        add_tasks "URL_CHECK#${URL}#$cmdpid"
      done
    fi
  fi
}

CONTINUOUS_LOCAL_CONTAINERS_SETUP() {
  add_tasks CONTINUOUS_LOCAL_CONTAINERS_SETUP setup_local_containers
}

DEPENDS_ON_SERVICES_CHECK() {
  cmdpid=$1
  if [ "$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})" == "OK" ]; then
    add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "DEPENDS_ON_SERVICES_CHECK#$cmdpid"
  else
    log 'info' "Services ${DEPENDS_ON_SERVICES} NO MORE AVAILABLE(S)"
    kill_cmdpid $cmdpid
  fi
}

DEPENDS_ON_URL_CHECK() {
  URL=$1
  cmdpid=$2
  if call_availability ${URL}; then
    log 'availability' "${URL} URL *STILL* AVAILABLE"
    add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "DEPENDS_ON_URL_CHECK#${URL}#$cmdpid"
  else
    log 'info' "${URL} NO MORE AVAILABLE"
    kill_cmdpid $cmdpid
  fi
}

URL_CHECK() {
  URL=$1
  cmdpid=$2
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
      add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "WAIT_FOR_URL#${URL}"
    fi
  else # ping url
    if safe_ping $URL; then
      log 'availability' "${URL} URL PING AVAILABLE"
    else
      log 'availability' "Still WAITING for $URL PING"
      if [[ "${URL}" == *_local* ]]; then
        add_tasks 'setup_local_containers'
      fi
      add_tasks "SLEEP#${CHECK_DEPENDENCIES_INTERVAL}" "WAIT_FOR_URL#${URL}"
    fi
  fi
}

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106

function call_eureka() {
  if hash curl 2>/dev/null; then
      echo $(curl --max-time ${CHECK_DEPENDENCIES_INTERVAL} -s "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@")
  else
      echo $(wget --timeout=${CHECK_DEPENDENCIES_INTERVAL} -q -O - "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@")
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
  # http://blog.jonathanargentiero.com/docker-sed-cannot-rename-etcsedl8ysxl-device-or-resource-busy/
  cp /etc/hosts ~/hosts.new

  ## CONTAINERS=$(call_eureka /containers)

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
}

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

# https://stackoverflow.com/questions/26177059/refresh-net-core-somaxcomm-or-any-sysctl-property-for-docker-containers/26197875#26197875
# https://stackoverflow.com/questions/26050899/how-to-mount-host-volumes-into-docker-containers-in-dockerfile-during-build
# docker run ... -v /proc:/writable-proc ...
disable_availability() {
  log "health" "DISABLING AVAILABILIY REQUESTED"

#  write_availability_file 503 "Service Unavailable" 19
  if [ -n "${available_pid}" ]; then
    kill -9 ${available_pid}
    export available_pid=0
  fi

  if [ -e /writable-proc/sys/net/ipv4/icmp_echo_ignore_all ]; then
    echo "1" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
  else
    log 'ping' "disabling ping not allowed"
  fi

  rm -f /availability.lock 2>/dev/null

  log "health" "AVAILABILIY DISABLED"
}

enable_availability() {
  log "health" "ENABLING AVAILABILIY REQUESTED"

  if [ "$AVAILABILITY_ALLOWED" != "false" ]; then
    ( while true; do echo "^C" | answer_availability ; done ) &
    export available_pid=$!
  fi

  if [ -e /writable-proc/sys/net/ipv4/icmp_echo_ignore_all ]; then
    echo "0" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
  fi

  echo "AVAILABLE" > /availability.lock

  log "health" "AVAILABILIY ENABLED"
}

safe_ping() {
  if [[ $(cat /proc/sys/net/ipv4/icmp_echo_ignore_all) == "0" ]]; then
    ping -c1 "$1" &>/dev/null
    return $?
  else
    if [[ $1 =~ _local[0-9]*$ ]]; then # The urls ending with _local[0-9]* are not known by Eureka...
      local url="${!1}" # https://stackoverflow.com/questions/14049057/bash-expand-variable-in-a-variable
      log 'ping' "${EUREKA_PROMPT}$1 resolved as ${url}"
    else
      local url="$1"
      log 'ping' "${EUREKA_PROMPT}$1 applied to ${url}"
    fi
    log 'ping' "${EUREKA_PROMPT}\$(call_eureka /ping/$url) = $(call_eureka /ping/$url)"
    test $(call_eureka /ping/$url) == "OK" &>/dev/null
    return $?
  fi
}

kill_cmdpid() {
  stop_tasks
  disable_availability &
  if [ "$KILL_WHEN_FAILED" = "true" ]; then
    log 'info' "pkill -P $1"
    pkill -P $1 &>/dev/null
  fi
}

#### AVAILABILITY ###

## https://www.computerhope.com/unix/nc.htm
function call_availability() {
  log 'netcat' "netcat -z -q 2 $1 ${EUREKA_AVAILABILITY_PORT}"
  netcat -z -q 2 $1 ${EUREKA_AVAILABILITY_PORT}
}

if ! hash netcat  2>/dev/null && [[ ! -f /usr/bin/netcat ]]; then ln -s $(which nc) /usr/bin/netcat; fi
if [[ $EUREKA_DEBUG = *netcat* ]]; then
  netcat -h
fi

answer_availability() {
  log 'netcat' "netcat -lk -q 1 -p ${EUREKA_AVAILABILITY_PORT}"
  netcat -lk -q 1 -p "${EUREKA_AVAILABILITY_PORT}"
}

#### Continuous Checks ####

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
    ( kill_cmdpid $cmdpid ) &
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
  disable_availability
else
  declare ready=$READINESS
fi
