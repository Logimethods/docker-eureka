# docker-service-registry

docker build -t service-registry-local .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 -e FLASK_DEBUG=1 service-registry-local

curl http://localhost:5000/container/id/serv
