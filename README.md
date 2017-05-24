# docker-service-registry

docker build -t service-registry-local .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock service-registry-local
