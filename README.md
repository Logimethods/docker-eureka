# docker-eureka

```
docker build -t eureka-local .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=1 logimethods/eureka
```
```
docker service create --network ${network} --name eureka --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=0 logimethods/eureka
```

```
entrypoint> docker build -t entrypoint-local .
docker run --rm --network ${network} --name entrypoint entrypoint-local env
```
```
docker run --rm --network ${network} --name entrypoint logimethods/eureka;entrypoint env
```

xxx_url -> the first URL
xxx_url0 -> all the URLs
xxx_url1 -> URL 1
xxx_url{n} -> URL {n}

```
curl http://localhost:5000/container/id/<name>
curl http://localhost:5000/service/id/<string:node>/<string:name>
curl http://localhost:5000/services/node/<string:node>
curl http://localhost:5000/services
```

## TEST (Ping)

```
ping > docker build -t ping-local .
docker run --rm -it --network ${network} --name ping -e DEPENDS_ON=eureka;ping0 -e WAIT_FOR=www.eficode.com:80,www.docker.com:80 ping-local

docker run --rm -it --network ${network} --name ping0 ping-local 
>ctr C
```
`-e CHECK_DEPENDENCIES_INTERVAL=5`
```
docker run --rm -it --network ${network} logimethods/eureka:ping
```

<name> can be based on a Python Regex: https://docs.python.org/3.6/library/re.html

https://github.com/docker/swarm/issues/1106
