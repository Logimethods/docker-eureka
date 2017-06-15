FROM alpine:3.6

# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  curl jq bash

COPY entrypoint.sh eureka_utils.sh /
ENTRYPOINT ["/entrypoint.sh"]
