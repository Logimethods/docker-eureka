FROM alpine:3.6

# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  curl jq bash

EXPOSE 6868
ENV EUREKA_AVAILABILITY_PORT=6868

COPY entrypoint.sh eureka_utils.sh /
ENTRYPOINT ["/entrypoint.sh"]
