# https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
# https://github.com/Logimethods/docker-eureka
FROM entrypoint_exp as entrypoint

FROM alpine:3.6
# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  jq bash
COPY --from=entrypoint eureka_utils.sh /eureka_utils.sh
COPY --from=entrypoint entrypoint.sh /entrypoint.sh

# OPTIONAL
COPY entrypoint_insert.sh /entrypoint_insert.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ping eureka
