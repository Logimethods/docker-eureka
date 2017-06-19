# docker-eureka

## The Eureka Server

Provides a solution to [Proposal: Use Swarm place holders to supply target host and port to Docker run #1106](https://github.com/docker/swarm/issues/1106) & related issues.

### Start
To run it:
```
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=1 logimethods/eureka
```
or, as a service
```
docker service create --network ${network} --name eureka --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=0 logimethods/eureka
```

### Usage
#### As a service
```
curl http://localhost:5000/container/id/<name>
curl http://localhost:5000/service/id/<string:node>/<string:name>
curl http://localhost:5000/services/node/<string:node>
curl http://localhost:5000/services
```

Note: `<name>` can be a Python Regex: https://docs.python.org/3.6/library/re.html

#### Through a Container (that needs to be extended)
```
docker run --rm --network ${network} --name entrypoint -e SETUP_LOCAL_CONTAINERS=true -e EUREKA_LINE_START=">> " logimethods/eureka:entrypoint env
```

`xxx_url` -> the first URL
`xxx_url0` -> all the URLs
`xxx_url1` -> URL 1
`xxx_url{n}` -> URL {n}

## DEPENDS_ON & WAIT_FOR

Provides a solution to [Missing Depends_ON functionality during start process within docker-swarm #31333](https://github.com/moby/moby/issues/31333#issuecomment-303250242).

First, build the "ping" Image:
```
pushd ping
docker build -t ping_container .
popd
```
Make sure that the Eureka Server is started, then run on two separate terminals
* the Container that is _waiting_
```
docker run --rm -it --network ${network} --name ping -e DEPENDS_ON=eureka,ping0 -e WAIT_FOR=www.docker.com:80,eureka_local,ping0 -e CHECK_TIMEOUT=10 ping_container
```
* The Container that is _expected_
```
docker run --rm -it --network ${network} --name ping0 --sysctl net.ipv4.icmp_echo_ignore_all=1 -v /proc:/writable-proc -e READY_WHEN="seq=5" -e FAILED_WHEN="seq=20" -e KILL_WHEN_FAILED=true ping_container
```
or, as a service
```
docker run --rm -it --network ${network} --name ping0 --mount type=bind,source=/proc,destination=/writable-proc -e READY_WHEN="seq=5" -e FAILED_WHEN="seq=20" -e KILL_WHEN_FAILED=true ping_container
```

## `entrypoint.sh` MERGING

```
COPY --from=entrypoint eureka_utils.sh /eureka_utils.sh
COPY --from=entrypoint entrypoint.sh /entrypoint.sh
RUN head -n -1 /docker-entrypoint.sh > /merged_entrypoint.sh ; \
    tail -n +3  /entrypoint.sh >> /merged_entrypoint.sh \
    chmod +x /merged_entrypoint.sh
## RUN cat /merged_entrypoint.sh
```

## EXPERIMENTAL & DEV REFERENCES

* https://stackoverflow.com/questions/26177059/refresh-net-core-somaxcomm-or-any-sysctl-property-for-docker-containers/26197875#26197875
* https://stackoverflow.com/questions/26050899/how-to-mount-host-volumes-into-docker-containers-in-dockerfile-during-build

`-e CHECK_DEPENDENCIES_INTERVAL=5`
```
docker run --rm -it --network ${network} logimethods/eureka:ping
```


https://github.com/docker/swarm/issues/1106

Waiting for [Multi-Stage builds on docker hub](https://github.com/docker/hub-feedback/issues/1039)
