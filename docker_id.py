#!/usr/bin/python

## Docker

import docker

client = docker.from_env()

def get_service(name):
	services = client.services.list()
	for service in services:
		if service.name == name:
			return service
	return None

def get_container(name):
	containers = client.containers.list()
	for container in containers:
		if container.name.startswith(name):
			return container
	return None

containers = client.containers.list()

# RESTful server
# http://containertutorials.com/docker-compose/flask-simple-app.html

import logging
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello World!"

# http://flask.pocoo.org/docs/0.12/quickstart/#variable-rules
@app.route('/container/id/<name>')
def id(name):
    container = get_container(name)
    if container is not None:
        return container.id
    else:
        app.logger.debug('No container with a name starting with \'%s\'', name)
        return "None"

if __name__ == '__main__':
    app.run(host='0.0.0.0')
