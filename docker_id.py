#!/usr/bin/python

import docker

client = docker.from_env()
services = client.services.list()
print(services)
