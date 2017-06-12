#!/bin/bash
set -e

# An alternative to https://github.com/docker/swarm/issues/1106
# export DOCKER_TARGET_ID=$(docker ps | grep $DOCKER_TARGET_NAME | awk '{ print $1 }')
#

: ${EUREKA_URL:=eureka}
: ${EUREKA_PORT:=5000}

if [ -z "$NODE_ID" ]
then
    SERVICES=$(curl -s http://${EUREKA_URL}:${EUREKA_PORT}/services)
else
    SERVICES=$(curl -s http://${EUREKA_URL}:${EUREKA_PORT}/services/node/${NODE_ID})
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
#done < <(curl -s http://localhost:5000/services/node/jn02f6tvsb5zdzzey3uxm6ae2 | jq '.[] | tostring' | sed -e 's/\"{\\\"/ip_/g' -e 's/\\\"\:\[\\\"/=/g' -e 's/\\\",\\\"/\\\ /g' -e 's/\\\"]}\"//g' )

if [ "$DEBUG" = "true" ]; then
  echo $EUREKA_URL:$EUREKA_PORT
  env | grep _url | sort
fi

exec "$@"
