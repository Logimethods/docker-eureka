#!/usr/bin/python

## Docker

import docker
import re

client = docker.from_env()


def get_services(name):
    pattern = re.compile(name)
    services = client.services.list()
    selected = []
    for service in services:
        if pattern.match(service.name):
            selected.append(service)
    return selected

def addServiceName(d, name):
    d.update({'ServiceName':name})
    return d

def get_tasks(node, name):
    pattern = re.compile(name)
    services = client.services.list()
    selected = []
    for service in services:
        if pattern.match(service.name):
            selected.extend([addServiceName(d, service.name) for d in service.tasks({'node':node, 'desired-state':'running'})])
    return selected

def get_container(name):
    pattern = re.compile(name)
    containers = client.containers.list()
    for container in containers:
        if pattern.match(container.name):
            return container
    return None

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
        app.logger.debug('No container with a name as \'%s\'', name)
        return "None"

@app.route('/container/name/<name>')
def name(name):
    container = get_container(name)
    if container is not None:
        return container.name
    else:
        app.logger.debug('No container with a name as \'%s\'', name)
        return "None"

@app.route('/service/id/<string:node>/<string:name>')
def service_id(node, name):
    tasks = get_tasks(node, name)
    if len(tasks) >= 1 :
        task = tasks[0]
        return task['Status']['ContainerStatus']['ContainerID']
    else:
        app.logger.debug('No service with a name as \'%s\' on %s node', name, node)
        return "None"

@app.route('/service/name/<string:node>/<string:name>')
def service_name(node, name):
    tasks = get_tasks(node, name)
    if len(tasks) >= 1 :
        name = task['ServiceName']
        task = tasks[0]
        slot = task.get('Slot', task['NodeID'])
        id = task['ID']
        return name + '.' + str(slot) + '.' + str(id)
    else:
        app.logger.debug('No service with a name as \'%s\' on %s node', name, node)
        return "None"

if __name__ == '__main__':
    app.run(host='0.0.0.0')
