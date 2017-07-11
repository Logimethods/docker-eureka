#!/bin/bash

pushd eureka
docker build -t eureka_exp .
popd

pushd entrypoint
docker build -t entrypoint_exp .
popd

pushd ping_exp
docker build -t ping_exp .
popd

pushd ping_ubuntu_exp
docker build -t ping_ubuntu_exp .
popd
