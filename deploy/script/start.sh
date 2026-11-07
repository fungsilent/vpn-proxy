#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
lock_deployment
load_config
"${compose[@]}" config --quiet
docker info >/dev/null
install -d -m 700 "$repo_root/.data/wireguard"
tmp=$(mktemp "$repo_root/.data/wireguard/wg0.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
prepare_vpn_config "$vpn_config" "$tmp"
"${compose[@]}" pull vpn
"${compose[@]}" build --pull
mv -- "$tmp" "$repo_root/.data/wireguard/wg0.conf"
"${compose[@]}" up -d --force-recreate --wait --wait-timeout 120
check_proxy
printf 'VPN proxy ready at %s.\n' "$proxy_url"
printf 'VPN config: %s\n' "${vpn_config##*/}"
