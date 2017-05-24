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

https://github.com/docker/swarm/issues/1106
