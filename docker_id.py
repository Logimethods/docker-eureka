#!/usr/bin/python

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
print(containers)

print(get_container('serv'))

# RESTful server
# http://containertutorials.com/docker-compose/flask-simple-app.html

from flask import Flask
from flask import request
app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello World!"

@app.route('/id')
def id():
    # here we want to get the id of a container (i.e. ?name=some-value)
    name = request.args.get('name')
    return get_container(name).id

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0')
