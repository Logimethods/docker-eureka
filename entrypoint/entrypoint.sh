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

: ${CHECK_DEPENDENCIES_DELAY:=2}

#### Initial Checks ####

# https://docs.docker.com/compose/startup-order/
if [ "${DEPENDS_ON}" ]; then
  >&2 echo "Checking DEPENDENCIES ${DEPENDS_ON}"
  until [ "$(call_eureka http://${EUREKA_URL}:${EUREKA_PORT}/dependencies/${DEPENDS_ON})" == "OK" ]; do
    >&2 echo "Still WAITING for Dependencies ${DEPENDS_ON}"
    sleep ${CHECK_DEPENDENCIES_DELAY}
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
      sleep ${CHECK_DEPENDENCIES_DELAY}
    done
  done
fi


#### Continuous Checks ####

check_dependencies(){
  dependencies_checked=$(call_eureka http://${EUREKA_URL}:${EUREKA_PORT}/dependencies/${DEPENDS_ON})
  if [ "$dependencies_checked" != "OK" ]; then
    >&2 echo "Failed Check Dependencies ${DEPENDS_ON}"
    if [ -z "$1" ]                           # Is parameter #1 zero length?
    then
      exit 1  # Or no parameter passed.
    else
      kill $1
    fi
  fi
}

infinite_check(){
  if [ "${DEPENDS_ON}" ]; then
    while true
    do
      sleep ${CHECK_DEPENDENCIES_DELAY}
      check_dependencies $1 &
    done
  fi
}

### EXEC CMD ###

( cmdpid=$BASHPID; (infinite_check $cmdpid) & exec "$@" )
