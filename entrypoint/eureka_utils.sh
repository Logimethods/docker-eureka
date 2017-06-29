#!/bin/bash

# https://stackoverflow.com/questions/10735574/include-source-script-if-it-exists-in-bash
include () {
    #  [ -f "$1" ] && source "$1" WILL EXIT...
    if [ -f $1 ]; then
        echo "source $1"
        source $1
    fi
}

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106

call_eureka() {
    if hash curl 2>/dev/null; then
        curl -s "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@"
    else
        wget -q -O - "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@"
    fi
}

add_dns_entry() {
  target=$2
  host=$1
  # https://stackoverflow.com/questions/24991136/docker-build-could-not-resolve-archive-ubuntu-com-apt-get-fails-to-install-a
  ip=$(nslookup ${target} 2>/dev/null | tail -n1 | awk '{ print $3 }')
  # http://jasani.org/2014/11/19/docker-now-supports-adding-host-mappings/
  sed -i "/${host}\$/d" ~/hosts.new
  echo "$ip $host" >> ~/hosts.new
}

setup_local_containers() {
  if [ -n "${NODE_ID}" ] || [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ]; then
    # http://blog.jonathanargentiero.com/docker-sed-cannot-rename-etcsedl8ysxl-device-or-resource-busy/
    cp /etc/hosts ~/hosts.new

    if [ -z "$NODE_ID" ]; then
        SERVICES=$(call_eureka /services)
    else
        SERVICES=$(call_eureka /services/node/${NODE_ID})
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

    if [ "$DEBUG" = "true" ]; then
      echo $EUREKA_URL_INTERNAL:$EUREKA_PORT
      env | grep _local | sort
      echo "---------"
      cat /etc/hosts
    fi
  fi
}

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

# https://stackoverflow.com/questions/26177059/refresh-net-core-somaxcomm-or-any-sysctl-property-for-docker-containers/26197875#26197875
# https://stackoverflow.com/questions/26050899/how-to-mount-host-volumes-into-docker-containers-in-dockerfile-during-build
# docker run ... -v /proc:/writable-proc ...
desable_ping() {
  if [ "$DEBUG" = "true" ]; then whoami; fi
  echo "1" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
}

enable_ping() {
  if [ "$DEBUG" = "true" ]; then whoami; fi
  echo "0" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
}

safe_ping() {
  if [[ $(cat /proc/sys/net/ipv4/icmp_echo_ignore_all) == "0" ]]; then
    ping -c1 "$1" &>/dev/null
    return $?
  else
    if [[ $1 =~ _local[0-9]*$ ]]; then # The urls ending with _local[0-9]* are not known by Eureka...
      local url="${!1}" # https://stackoverflow.com/questions/14049057/bash-expand-variable-in-a-variable
    else
      local url="$1"
    fi
    test $(call_eureka /ping/$url) == "OK"
    return $?
  fi
}

kill_cmdpid () {
  declare cmdpid=$1
  # http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
  # Be nice, post SIGTERM first.
  # The 'exit 0' below will be executed if any preceeding command fails.
  kill -s SIGTERM $cmdpid && kill -0 $cmdpid || exit 0
  sleep $delay
  kill -s SIGKILL $cmdpid
}

#### Initial Checks ####

initial_check() {
  declare cmdpid=$1

  #### SETUP timeout
  if [ -n "${CHECK_TIMEOUT}" ]; then
    # http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
    declare -i timeout=CHECK_TIMEOUT
    (
        for ((t = timeout; t > 0; t -= interval)); do
            echo "$t Second(s) Remaining Before Timeout"
            sleep $interval
            # kill -0 pid   Exit code indicates if a signal may be sent to $pid process.
            kill -0 $$ || exit 0
        done

        echo "Timeout. Will EXIT"
        # Be nice, post SIGTERM first.
        # The 'exit 0' below will be executed if any preceeding command fails.
        kill -s SIGTERM $cmdpid && kill -0 $cmdpid || exit 0
        sleep $delay
        kill -s SIGKILL $cmdpid
    ) 2> /dev/null &

    # $! expands to the PID of the last process executed in the background.
    timeout_pid=$!
    # https://stackoverflow.com/questions/5719030/bash-silently-kill-background-function-process
    disown
  fi

  # https://docs.docker.com/compose/startup-order/
  if [ -n "${DEPENDS_ON}" ]; then
    >&2 echo "Checking DEPENDENCIES ${DEPENDS_ON}"
    until [ "$(call_eureka /dependencies/${DEPENDS_ON})" == "OK" ]; do
      >&2 echo "Still WAITING for Dependencies ${DEPENDS_ON}"
      sleep $interval
    done
  fi

  # https://github.com/Eficode/wait-for
  if [ -n "${WAIT_FOR}" ]; then
    >&2 echo "Checking URLS $WAIT_FOR"
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      if [[ $URL == *":"* ]]; then # url + port
        HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
        PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
        until nc -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ; [ $result -eq 0 ] ; do
          >&2 echo "Still WAITING for URL $HOST:$PORT"
          sleep $interval
          setup_local_containers &
        done
      else # ping url
        until safe_ping $URL; do
          >&2 echo "Still WAITING for $URL PING"
          sleep $interval
          setup_local_containers &
        done
      fi
    done
  fi

  # Kill the CHECK_TIMEOUT loop if still alive
  if [ -n "${CHECK_TIMEOUT}" ]; then
    echo "KILL KILL ! $timeout_pid / $cmdpid"
    kill $timeout_pid
  fi
}

#### Continuous Checks ####

check_dependencies(){
  declare cmdpid=$1

  if [ -n "${DEPENDS_ON}" ]; then
    dependencies_checked=$(call_eureka /dependencies/${DEPENDS_ON})
    if [ "$dependencies_checked" != "OK" ]; then
      >&2 echo "Failed Check Dependencies ${DEPENDS_ON}"
      kill_cmdpid $cmdpid
    fi
  fi

  # https://github.com/Eficode/wait-for
  if [ -n "${WAIT_FOR}" ]; then
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      if [[ $URL == *":"* ]]; then # url + port
        HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
        PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
        nc -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ;
        if [ $result -ne 0 ] ; then
          >&2 echo "Failed Check URL ${URL}"
          kill_cmdpid $cmdpid
        fi
      elif ! ping -c 1 "$URL" &>/dev/null ; then # ping url
        >&2 echo "Failed ${URL} Ping"
        kill_cmdpid $cmdpid
      fi
    done
  fi
}

infinite_setup_check(){
  if [ -n "${SETUP_LOCAL_CONTAINERS}" ] || [ -n "${EUREKA_URL}" ] || [ -n "${DEPENDS_ON}" ] || [ -n "${WAIT_FOR}" ]; then
    while true
    do
      setup_local_containers &
      sleep $interval
      if [ -n "${DEPENDS_ON}" ] || [ -n "${WAIT_FOR}" ]; then
        check_dependencies $1 &
      fi
    done
  fi
}

infinite_monitor(){
  if [ -n "${READY_WHEN}" ] | [ -n "${READY_WHEN}" ]; then
    exec 1> >(
    while read line
    do
      >&2 echo "${EUREKA_LINE_START}${line}"
      monitor_output "$line" $1
    done
    )
  fi
}

monitor_output() {
  declare cmdpid=$2

  if [ "$ready" = false ] && [[ $1 == *"${READY_WHEN}"* ]]; then
    >&2 echo "EUREKA READY!"

    ## Optional finalizing
    include entrypoint_finalize.sh

    ready="$READINESS"
    enable_ping &
  fi
  if [ "$ready" = true ] && [[ $1 == *"${FAILED_WHEN}"* ]]; then
    >&2 echo "EUREKA FAILED!"
    if [ "$KILL_WHEN_FAILED" = "true" ]; then
      kill_cmdpid $cmdpid
    else
      ready=false
      desable_ping &
    fi
  fi
}

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106

EUREKA_URL_INTERNAL=${EUREKA_URL}
: ${EUREKA_URL_INTERNAL:=eureka}
: ${EUREKA_PORT:=5000}

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

: ${CHECK_DEPENDENCIES_INTERVAL:=2}
: ${CHECK_KILL_DELAY:=5}

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
  desable_ping
else
  declare ready=$READINESS
fi
