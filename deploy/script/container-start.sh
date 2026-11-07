#!/bin/sh
set -eu
# Use Gluetun's resolver in the shared namespace, not Docker's host-side resolver.
printf 'nameserver 127.0.0.1\n' > /etc/resolv.conf
exec tinyproxy -d -c /etc/tinyproxy/tinyproxy.conf
