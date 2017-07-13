# EUReKA (Dependencies Management & Direct Access to Containers)

/!\ Work still in progress

Provides a solution to [Proposal: Use Swarm place holders to supply target host and port to Docker run #1106](https://github.com/docker/swarm/issues/1106) & related issues, also to [Missing Depends_ON functionality during start process within docker-swarm #31333](https://github.com/moby/moby/issues/31333#issuecomment-303250242).

## The EUReKA Server

### Start
To run it:
```
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=1 logimethods/eureka
```
or, as a service
```
docker service create --network ${network} --constraint=node.role==manager --name eureka --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=0 logimethods/eureka
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
docker run --rm --network ${network} --name entrypoint --constraint=node.role!=manager -e NODE_ID={{.Node.ID}} -e EUREKA_LINE_START=">> " logimethods/eureka:entrypoint env
```

`xxx_url` -> the first URL
`xxx_url0` -> all the URLs
`xxx_url1` -> URL 1
`xxx_url{n}` -> URL {n}

## DEPENDS_ON & WAIT_FOR
### DEPENDS_ON
Is especting the targeted Container to answer on port `${EUREKA_AVAILABILITY_PORT}` (by default `6868`).

### WAIT_FOR
Is especting the targeted Container to answer to the `ping` request.

## READY_WHEN & FAILED_WHEN
### READY_WHEN
Makes the Container Available when the provided string is catched on the log.

_Tip_: to be able to desable the ping answer of a container, the `/proc:/writable-proc` volume has to be set.
### FAILED_WHEN
Makes the Container Unavailable when the provided string is catched on the log.

_Note_: If `$KILL_WHEN_FAILED` is set to `true`, the Caontainer will then be killed.

## Usage

_Note_, first build the Docker Images: 
```
> ./build_exp.sh 
```

### `docker run` / `docker service`

To build a "ping" Image:
```
pushd ping
docker build -t ping_container .
popd
```
Make sure that the Eureka Server is started, then run on two separate terminals
* the Container that is _waiting_
```
docker run --rm -it --network ${network} --name ping -v /proc:/writable-proc -e DEPENDS_ON=eureka,ping0 -e WAIT_FOR=www.docker.com:80,eureka_local,ping0 -e SETUP_LOCAL_CONTAINERS=true -e CHECK_TIMEOUT=25 ping_container ping eureka_local
```
* The Container that is _expected_
```
docker run --rm -it --network ${network} --name ping0 --sysctl net.ipv4.icmp_echo_ignore_all=1 -v /proc:/writable-proc -e READY_WHEN="seq=5" -e FAILED_WHEN="seq=20" -e KILL_WHEN_FAILED=true ping_container ping www.docker.com
```
or, as a service
```
docker run --rm -it --network ${network} --name ping0 --mount type=bind,source=/proc,destination=/writable-proc -e READY_WHEN="seq=5" -e FAILED_WHEN="seq=20" -e KILL_WHEN_FAILED=true ping_container ping www.docker.com
```

### `docker stack`

```
docker stack deploy -c docker-compose.yml test
```

## Setup of the Dockerfile
* Alpine, see https://github.com/Logimethods/docker-eureka/blob/master/ping_alpine_exp/Dockerfile
* Ubuntu, see https://github.com/Logimethods/docker-eureka/blob/master/ping_ubuntu_exp/Dockerfile
* Debian, see https://github.com/Logimethods/docker-eureka/blob/master/ping_debian_exp/Dockerfile

# References to EUReKA

* https://github.com/Logimethods/smart-meter/tree/multi-stage-build

# New features (?)

* https://docs.docker.com/engine/reference/builder/#healthcheck

# EXPERIMENTAL & DEV REFERENCES

* https://stackoverflow.com/questions/26177059/refresh-net-core-somaxcomm-or-any-sysctl-property-for-docker-containers/26197875#26197875
* https://stackoverflow.com/questions/26050899/how-to-mount-host-volumes-into-docker-containers-in-dockerfile-during-build

`-e CHECK_DEPENDENCIES_INTERVAL=5`
```
docker run --rm -it --network ${network} logimethods/eureka:ping
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


https://github.com/docker/swarm/issues/1106

Waiting for [Multi-Stage builds on docker hub](https://github.com/docker/hub-feedback/issues/1039)
