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
docker run --rm -it --network ${network} --name ping -e DEPENDS_ON=eureka,ping0 -e WAIT_FOR=www.docker.com:80,eureka_local,ping0 -e CHECK_TIMEOUT=10 ping-local

docker run --rm -it --network ${network} --name ping0 -v /proc:/writable-proc -e READY_WHEN="seq=5" -e FAILED_WHEN="seq=20" -e KILL_WHEN_FAILED=true ping-local

docker run --rm -it --network ${network} --privileged ping-local sh
#### https://tecadmin.net/block-ping-responses-in-linux/#
#### https://github.com/moby/moby/issues/4717
/ # echo "1" >  /proc/sys/net/ipv4/icmp_echo_ignore_all
```

```
#### https://stackoverflow.com/questions/26177059/refresh-net-core-somaxcomm-or-any-sysctl-property-for-docker-containers/26197875#26197875
#### https://stackoverflow.com/questions/26050899/how-to-mount-host-volumes-into-docker-containers-in-dockerfile-during-build
docker run --rm -it --network ${network} -v /proc:/writable-proc ping-local sh
/ # echo "1" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
/ # sysctl net.ipv4.icmp_echo_ignore_all
net.ipv4.icmp_echo_ignore_all = 1
/ # echo "0" >  /writable-proc/sys/net/ipv4/icmp_echo_ignore_all
/ # sysctl net.ipv4.icmp_echo_ignore_all
net.ipv4.icmp_echo_ignore_all = 0
```

`-e CHECK_DEPENDENCIES_INTERVAL=5`
```
docker run --rm -it --network ${network} logimethods/eureka:ping
```

<name> can be based on a Python Regex: https://docs.python.org/3.6/library/re.html

https://github.com/docker/swarm/issues/1106

Waiting for [Multi-Stage builds on docker hub](https://github.com/docker/hub-feedback/issues/1039)
