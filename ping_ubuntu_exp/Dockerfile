# https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
# https://github.com/Logimethods/docker-eureka
FROM entrypoint_exp as entrypoint

### MAIN FROM ###

FROM ubuntu:17.04
# https://stedolan.github.io/jq/
RUN apt-get update && apt-get install -y \
  jq bash netcat-openbsd curl iputils-ping dnsutils

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
