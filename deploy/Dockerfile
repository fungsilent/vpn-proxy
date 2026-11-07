FROM alpine:3.24.4
RUN apk add --no-cache tinyproxy curl
COPY deploy/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY --chmod=755 deploy/script/container-start.sh /usr/local/bin/container-start
ENTRYPOINT ["/usr/local/bin/container-start"]
