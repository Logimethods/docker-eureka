#!/bin/bash

docker build -t logimethods/eureka-local .

pushd entrypoint
docker build -t logimethods/entrypoint-local .
popd

pushd ping
docker build -t logimethods/ping-local .
popd
