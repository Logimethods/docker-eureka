# docker-service-registry

```
docker build -t service-registry-local .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=1 logimethods/service-registry

docker service create --name registry --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=0 logimethods/service-registry
```

```
curl http://localhost:5000/container/id/<name>
curl http://localhost:5000/service/id/<string:node>/<string:name>
```

<name> can be based on a Python Regex: https://docs.python.org/3.6/library/re.html

https://github.com/docker/swarm/issues/1106
