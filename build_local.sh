#!/bin/bash

pushd entrypoint
docker build -t entrypoint-local .
popd

pushd ping
docker build -t ping-local .
popd
