#!/bin/bash

set -e

pushd eureka
docker build -t logimethods/eureka .
docker push logimethods/eureka
popd

pushd entrypoint
docker build -t logimethods/eureka:entrypoint .
docker push logimethods/eureka:entrypoint
popd
