#!/bin/bash

docker build -t eureka_exp .

pushd entrypoint
docker build -t entrypoint_exp .
popd

pushd ping_exp
docker build -t ping_exp .
popd
