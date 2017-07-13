## MIT License
##
## Copyright (c) 2017 Logimethods
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.

#!/usr/bin/python

## Docker

# https://github.com/docker/docker-py
import docker
import re
import json

## https://stackoverflow.com/questions/2953462/pinging-servers-in-python
from platform import system as system_name # Returns the system/OS name
from os import system as system_call       # Execute a shell command

def check_ping(host):
    """
    Returns True if host (str) responds to a ping request.
    Remember that some hosts may not respond to a ping request even if the host name is valid.
    """
    # Ping parameters as function of OS
    parameters = "-n 1" if system_name().lower()=="windows" else "-c 1"
    # Pinging
    return system_call("ping " + parameters + " " + host) == 0


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

def get_tasks(node):
    services = client.services.list()
    tasks = []
    for service in services:
        tasks.append([addServiceName(d, service.name) for d in service.tasks({'node':node, 'desired-state':'running'})])
    return tasks

def get_container(name):
    pattern = re.compile(name)
    containers = client.containers.list()
    for container in containers:
        if pattern.match(container.name):
            return container
    return None

def extract_container(service, task):
    slot = task.get('Slot', task['NodeID'])
    id = task['ID']
    return service + '.' + str(slot) + '.' + str(id)

def get_containers_from_tasks(service, tasks):
    containers = []
    if tasks: # List not empty
        containers.append({service.name:[extract_container(service.name, d) for d in tasks]})
        # To handle stacks
        labels = service.attrs["Spec"]['Labels']
        if 'com.docker.stack.namespace' in labels:
            namespace = labels['com.docker.stack.namespace']
            short_name = service.name[len(namespace)+1:]
            containers.append({short_name:[extract_container(service.name, d) for d in tasks]})
    return containers

def get_containers(node):
    services = client.services.list()
    containers = []
    for service in services:
        tasks = service.tasks({'node':node, 'desired-state':'running'})
        containers.extend(get_containers_from_tasks(service, tasks))
    return containers

def get_all_containers():
    services = client.services.list()
    containers = []
    for service in services:
        tasks = service.tasks({'desired-state':'running'})
        containers.extend(get_containers_from_tasks(service, tasks))
    return containers

def check_dependencies(str):
    containers = []
    for container in client.containers.list():
        containers.append(container.name)
        # To handle stacks. /!\ Not 100% accurate since the client could be on another stack...
        labels = container.labels
        if 'com.docker.stack.namespace' in labels:
            namespace = labels['com.docker.stack.namespace']
            short_name = container.name[len(namespace)+1:]
            containers.append(short_name)
    for service in client.services.list():
        tasks = service.tasks({'desired-state':'running'})
        if tasks: # List not empty
            containers.append(service.name)
            # To handle stacks. /!\ Not 100% accurate since the client could be on another stack...
            labels = service.attrs["Spec"]['Labels']
            if 'com.docker.stack.namespace' in labels:
                namespace = labels['com.docker.stack.namespace']
                short_name = service.name[len(namespace)+1:]
                containers.append(short_name)
    dependencies = str.split(',')
    for dependency in dependencies:
        if dependency not in containers:
            return ''
    return 'OK'

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
        task = tasks[0]
        name = task['ServiceName']
        slot = task.get('Slot', task['NodeID'])
        id = task['ID']
        return name + '.' + str(slot) + '.' + str(id)
    else:
        app.logger.debug('No service with a name as \'%s\' on %s node', name, node)
        return "None"

@app.route('/services/node/<string:node>')
def services_node(node):
    return json.dumps(get_containers(node))

@app.route('/services')
def services():
    return json.dumps(get_all_containers())

@app.route('/dependencies/<string:str>')
def dependencies(str):
    return check_dependencies(str)

@app.route('/ping/<string:str>')
def ping(str):
    return "OK" if check_ping(str) else "KO"

if __name__ == '__main__':
    app.run(host='0.0.0.0')
