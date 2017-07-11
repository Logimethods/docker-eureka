# https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
# https://github.com/Logimethods/docker-eureka
FROM logimethods/eureka:entrypoint as entrypoint

### MAIN FROM ###

FROM alpine:3.6
# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  jq bash netcat-openbsd

COPY --from=entrypoint eureka_utils.sh /eureka_utils.sh
COPY --from=entrypoint entrypoint.sh /entrypoint.sh
COPY --from=entrypoint eureka_utils_alpine.sh /eureka_utils_extended.sh

# OPTIONAL
COPY entrypoint_insert.sh /entrypoint_insert.sh
COPY entrypoint_finalize.sh /entrypoint_finalize.sh
COPY entrypoint_prepare.sh /entrypoint_prepare.sh

# EXPOSE 6868
# ENV EUREKA_AVAILABILITY_PORT=6868

ENTRYPOINT ["/entrypoint.sh"]
CMD ping eureka
