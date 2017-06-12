# https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
FROM logimethods/eureka:entrypoint as entrypoint

FROM alpine:3.6
# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  curl jq bash
COPY --from=entrypoint entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ping ${eureka_url} -c 3
