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

function call_eureka() {
    if hash curl 2>/dev/null; then
        echo $(curl -s "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@")
    else
        echo $(wget -q -O - "http://${EUREKA_URL_INTERNAL}:${EUREKA_PORT}$@")
    fi
}

function call_availablility() {
    if hash curl 2>/dev/null; then
        echo $(curl -s "http://$@:${EUREKA_AVAILABILITY_PORT}")
    else
        echo $(wget -q -O - "http://$@:${EUREKA_AVAILABILITY_PORT}")
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

    if [[ $DEBUG = *services* ]]; then
      echo "SERVICES: $SERVICES"
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

    if [[ $DEBUG = *trace* ]]; then
      echo $EUREKA_URL_INTERNAL:$EUREKA_PORT
      env | grep -v _local | sort
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
  if [[ $DEBUG = *ping* ]]; then echo "desable_ping asked" ; fi

  if [ "$AVAILABILITY_ALLOWED" != "false" ]; then
    # https://github.com/docker-library/busybox/issues/32
    write_availability_file 503 "Service Unavailable" 19
  fi

  if [ "$PING_ALLOWED" != "false" ]; then
    echo "1" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
  else
    echo "desable_ping not allowed"
  fi
}

enable_ping() {
  if [[ $DEBUG = *ping* ]]; then echo "enable_ping asked"; fi

  if [ "$AVAILABILITY_ALLOWED" != "false" ]; then
    write_availability_file 200 "OK" 2
  fi

  if [ "$PING_ALLOWED" != "false" ]; then
    echo "0" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
  fi
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
    desable_ping &
  fi
}

#### AVAILABILITY ###

write_availability_file() {
cat >/eureka_availability.txt <<EOL
HTTP/1.1 ${1} ${2}
Content-Type: text/plain
Content-Length: ${3}
Connection: close

${2}
EOL
}

setup_availability() {
  if [ "$AVAILABILITY_ALLOWED" != "false" ]; then
    # https://github.com/docker-library/busybox/issues/32
    write_availability_file 503 "Service Unavailable" 19
    (while true; do cat /eureka_availability.txt | nc -l -p 6868 >/dev/null; done) &
#    (while true; do echo "OK    " | nc -l -p 6868; done) &
  fi
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
  if [ -n "${DEPENDS_ON_SERVICES}" ]; then
    >&2 echo "Checking SERVICE DEPENDENCIES ${DEPENDS_ON_SERVICES}"
    until [ "$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})" == "OK" ]; do
      >&2 echo "Still WAITING for Service Dependencies ${DEPENDS_ON_SERVICES}"
      sleep $interval
    done
  fi

  if [ -n "${DEPENDS_ON}" ]; then
    >&2 echo "Checking DEPENDENCIES ${DEPENDS_ON}"
    URLS=$(echo $DEPENDS_ON | tr "," "\n")
    for URL in $URLS
    do
      until [ "$(call_availablility ${URL})" ]; do
        >&2 echo "Still WAITING for Dependencies ${URL}"
        sleep $interval
      done
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

  if [ -n "${DEPENDS_ON_SERVICES}" ]; then
    dependencies_checked=$(call_eureka /dependencies/${DEPENDS_ON_SERVICES})
    if [ "$dependencies_checked" != "OK" ]; then
      >&2 echo "Failed Check Services Dependencies ${DEPENDS_ON_SERVICES}"
      kill_cmdpid $cmdpid
    fi
  fi

  if [ -n "${DEPENDS_ON}" ]; then
    URLS=$(echo $DEPENDS_ON | tr "," "\n")
    for URL in $URLS
    do
      if ! [ "$(call_availablility ${URL})" ]; then
        >&2 echo "Failed ${URL} Availability"
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
        nc -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ;
        if [ $result -ne 0 ] ; then
          >&2 echo "Failed Check URL ${URL}"
          if [ "$KILL_WHEN_FAILED" = "true" ]; then
            kill_cmdpid $cmdpid
          fi
        fi
      elif ! safe_ping $URL ; then # ping url
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
  if [[ $DEBUG = *monitor* ]]; then
    >&2 echo "infinite_monitor ASKED";
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

    if [[ $DEBUG = *monitor* ]]; then
      >&2 echo "infinite_monitor STARTED";
    fi
  fi
}

monitor_output() {
  declare cmdpid=$2

  if [[ $DEBUG = *tracemonitor* ]]; then
    >&2 echo "Monitor: ready=${ready}, input='${1}'";
  fi

  if [ "$ready" = false ] && [[ $1 == *"${READY_WHEN}"* ]]; then
    >&2 echo "EUREKA: FINALIZE!"

    ## Optional finalizing
    include entrypoint_finalize.sh

    >&2 echo "EUREKA: READY!"

    ready="$READINESS"
    enable_ping &
  fi
  if [ "$ready" = true ] && [[ $1 == *"${FAILED_WHEN}"* ]]; then
    >&2 echo "EUREKA: FAILED!"
    kill_cmdpid $cmdpid
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
