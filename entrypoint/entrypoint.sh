#!/bin/bash
set -e

### PROVIDE LOCAL URLS ###
# An alternative to https://github.com/docker/swarm/issues/1106
# export DOCKER_TARGET_ID=$(docker ps | grep $DOCKER_TARGET_NAME | awk '{ print $1 }')

: ${EUREKA_URL:=eureka}
: ${EUREKA_PORT:=5000}

call_eureka() {
    if hash curl 2>/dev/null; then
        curl -s "$@"
    else
        wget -q -O - "$@"
    fi
}

if [ -z "$NODE_ID" ]
then
    SERVICES=$(call_eureka http://${EUREKA_URL}:${EUREKA_PORT}/services)
else
    SERVICES=$(call_eureka http://${EUREKA_URL}:${EUREKA_PORT}/services/node/${NODE_ID})
fi

# https://stedolan.github.io/jq/
while IFS="=" read name value; do
  export "${name}=${value/%\ */}"
  export "${name}0=$value"
  i=1
  for container in $value; do
    export "${name}$((i++))=${container}"
  done
done < <( echo "$SERVICES" | jq '.[] | tostring' | sed -e 's/\"{\\\"//g' -e 's/\\\"\:\[\\\"/_url=/g' -e 's/\\\",\\\"/\\\ /g' -e 's/\\\"]}\"//g')

if [ "$DEBUG" = "true" ]; then
  echo $EUREKA_URL:$EUREKA_PORT
  env | grep _url | sort
fi

### CHECK DEPENDENCIES ###
# https://github.com/moby/moby/issues/31333#issuecomment-303250242

: ${CHECK_DEPENDENCIES_INTERVAL:=2}
: ${CHECK_KILL_DELAY:=5}

# Interval between checks if the process is still alive.
declare -i interval=CHECK_DEPENDENCIES_INTERVAL
# Delay between posting the SIGTERM signal and destroying the process by SIGKILL.
declare -i delay=CHECK_KILL_DELAY

initial_check() {
  declare cmdpid=$1

  #### SETUP timeout

  if [ "${CHECK_TIMEOUT}" ]; then
    # http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
    # Timeout.
    declare -i timeout=CHECK_TIMEOUT
    # kill -0 pid   Exit code indicates if a signal may be sent to $pid process.
    (
        ((t = timeout))

        while ((t > 0)); do
            echo "$t Second(s) Remaining Before Timeout"
            sleep $interval
            kill -0 $$ || exit 0
            ((t -= interval))
        done

        if ((started == 0)); then
          echo "Timeout. Will EXIT"
          # Be nice, post SIGTERM first.
          # The 'exit 0' below will be executed if any preceeding command fails.
          kill -s SIGTERM $cmdpid && kill -0 $cmdpid || exit 0
          sleep $delay
          kill -s SIGKILL $cmdpid
        fi
    ) 2> /dev/null &
  fi

  #### Initial Checks ####

  # https://docs.docker.com/compose/startup-order/
  if [ "${DEPENDS_ON}" ]; then
    >&2 echo "Checking DEPENDENCIES ${DEPENDS_ON}"
    until [ "$(call_eureka http://${EUREKA_URL}:${EUREKA_PORT}/dependencies/${DEPENDS_ON})" == "OK" ]; do
      >&2 echo "Still WAITING for Dependencies ${DEPENDS_ON}"
      sleep $interval
    done
  fi

  # https://github.com/Eficode/wait-for
  if [ "${WAIT_FOR}" ]; then
    >&2 echo "Checking URLS $WAIT_FOR"
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
      PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
      until nc -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ; [ $result -eq 0 ] ; do
        >&2 echo "Still WAITING for URL $HOST:$PORT"
        sleep $interval
      done
    done
  fi

  if [ "${CHECK_TIMEOUT}" ]; then
    # $! expands to the PID of the last process executed in the background.
    kill $!
  fi
}

#### Continuous Checks ####

check_dependencies(){
  declare cmdpid=$1

  if [ "${DEPENDS_ON}" ]; then
    dependencies_checked=$(call_eureka http://${EUREKA_URL}:${EUREKA_PORT}/dependencies/${DEPENDS_ON})
    if [ "$dependencies_checked" != "OK" ]; then
      >&2 echo "Failed Check Dependencies ${DEPENDS_ON}"
      # http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
      # Be nice, post SIGTERM first.
      # The 'exit 0' below will be executed if any preceeding command fails.
      kill -s SIGTERM $cmdpid && kill -0 $cmdpid || exit 0
      sleep $delay
      kill -s SIGKILL $cmdpid
    fi
  fi

  # https://github.com/Eficode/wait-for
  if [ "${WAIT_FOR}" ]; then
    URLS=$(echo $WAIT_FOR | tr "," "\n")
    for URL in $URLS
    do
      HOST=$(printf "%s\n" "$URL"| cut -d : -f 1)
      PORT=$(printf "%s\n" "$URL"| cut -d : -f 2)
      nc -z "$HOST" "$PORT" > /dev/null 2>&1 ; result=$? ;
      if [ $result -ne 0 ] ; then
        >&2 echo "Failed Check URL ${URLS}"
        # http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
        # Be nice, post SIGTERM first.
        # The 'exit 0' below will be executed if any preceeding command fails.
        kill -s SIGTERM $cmdpid && kill -0 $cmdpid || exit 0
        sleep $delay
        kill -s SIGKILL $cmdpid
      fi
    done
  fi
}

infinite_check(){
  if [[ "${DEPENDS_ON}" || "${CHECK_TIMEOUT}" ]]; then
    while true
    do
      sleep $interval
      check_dependencies $1 &
    done
  fi
}

### EXEC CMD ###
( cmdpid=$BASHPID;
  initial_check $cmdpid ;
  (infinite_check $cmdpid) & exec "$@" )
