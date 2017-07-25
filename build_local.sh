#!/bin/bash

set -e

pushd eureka
docker build -t logimethods/eureka-local .
popd

pushd entrypoint
docker build -t entrypoint_exp .
popd

pushd ping_exp
docker build -t ping_exp .
popd
