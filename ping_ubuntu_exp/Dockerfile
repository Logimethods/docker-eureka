# https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
# https://github.com/Logimethods/docker-eureka
FROM entrypoint_exp as entrypoint

FROM ubuntu
# https://stedolan.github.io/jq/
RUN apt-get update && apt-get install -y \
  jq bash netcat curl iputils-ping dnsutils

COPY --from=entrypoint eureka_utils.sh /eureka_utils.sh
COPY --from=entrypoint entrypoint.sh /entrypoint.sh
COPY --from=entrypoint eureka_utils_ubuntu.sh /eureka_utils_extended.sh

# OPTIONAL
COPY entrypoint_insert.sh /entrypoint_insert.sh
COPY entrypoint_finalize.sh /entrypoint_finalize.sh
COPY entrypoint_prepare.sh /entrypoint_prepare.sh

# EXPOSE 6868
# ENV EUREKA_AVAILABILITY_PORT=6868

ENTRYPOINT ["/entrypoint.sh"]
CMD ping eureka
