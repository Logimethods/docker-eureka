FROM alpine:3.6

# https://stedolan.github.io/jq/
RUN apk --no-cache add \
  curl jq bash

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
