#!/bin/bash

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

  if [[ $DEBUG = *dns* ]]; then
    echo "O ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    cat ~/hosts.new
    echo "1 ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "$host $target"
    echo "2 ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  fi

  # https://stackoverflow.com/questions/24991136/docker-build-could-not-resolve-archive-ubuntu-com-apt-get-fails-to-install-a
  ip=$(nslookup ${target} 2>/dev/null | tail -n1 | awk '{ print $3 }')

  # http://jasani.org/2014/11/19/docker-now-supports-adding-host-mappings/
  sed -i "/${host}\$/d" ~/hosts.new
  echo "$ip $host" >> ~/hosts.new

  if [[ $DEBUG = *dns* ]]; then
    echo "A ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "nslookup ${target} ="
    echo "$(nslookup ${target})"
    echo "B ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "$ip $host"
    echo "C ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    cat ~/hosts.new
    echo "D ~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  fi
}

ln -s $(which nc) /usr/bin/netcat
answer_availability() {
  netcat -lk -q 1 -p "${EUREKA_AVAILABILITY_PORT}"
}
