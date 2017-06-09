# docker-eureka

```
docker build -t eureka-local .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=1 logimethods/eureka

docker service create --name eureka --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=0 logimethods/eureka
```

```
entrypoint> docker build -t entrypoint-local .
docker run --rm --name entrypoint entrypoint-local env
```

```
curl http://localhost:5000/container/id/<name>
curl http://localhost:5000/service/id/<string:node>/<string:name>
curl http://localhost:5000/services/node/<string:node>
curl http://localhost:5000/services
```

<name> can be based on a Python Regex: https://docs.python.org/3.6/library/re.html

https://github.com/docker/swarm/issues/1106
