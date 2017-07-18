# https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
# https://github.com/Logimethods/docker-eureka
FROM entrypoint_exp as entrypoint

### MAIN FROM ###

FROM alpine:3.6
# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  jq bash netcat-openbsd>1.130

COPY --from=entrypoint eureka_utils.sh /eureka_utils.sh
COPY --from=entrypoint entrypoint.sh /entrypoint.sh

# OPTIONAL
COPY entrypoint_insert.sh /entrypoint_insert.sh
COPY entrypoint_finalize.sh /entrypoint_finalize.sh
COPY entrypoint_prepare.sh /entrypoint_prepare.sh

# EXPOSE 6868
# ENV EUREKA_AVAILABILITY_PORT=6868

HEALTHCHECK --interval=5s --timeout=1s --retries=1 CMD test -f /availability.lock

ENTRYPOINT ["/entrypoint.sh"]
CMD ping eureka
