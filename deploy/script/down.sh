#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
lock_deployment
load_config
exec "${compose[@]}" down
