#!/usr/bin/env bash

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compose=(docker compose --project-directory "$repo_root" --env-file "$repo_root/.env" -f "$repo_root/deploy/compose.yaml")

lock_deployment() {
    umask 077
    install -d -m 700 "$repo_root/.data"
    exec 9>"$repo_root/.data/deploy.lock"
    if ! flock -n 9; then
        echo 'Another deployment or VPN switch is running.' >&2
        exit 1
    fi
}

load_config() {
    if [[ ! -f "$repo_root/.env" ]]; then
        echo 'Missing root .env. Copy .env.example to .env and review it first.' >&2
        exit 1
    fi
    command -v docker >/dev/null || { echo 'Docker with Compose is required.' >&2; exit 1; }
    # Compose parses dotenv; never execute .env as shell code.
    resolved_env=$("${compose[@]}" config --environment | sed -n '/^\(VPN_CONFIG\|PROXY_PORT\)=/p')
    vpn_config=''
    proxy_port=''
    while IFS='=' read -r name value; do
        case "$name" in
            VPN_CONFIG) vpn_config=$value ;;
            PROXY_PORT) proxy_port=$value ;;
        esac
    done <<< "$resolved_env"
    if [[ "$vpn_config" != /* ]]; then
        echo 'VPN_CONFIG must be an absolute host path.' >&2
        exit 1
    fi
    if [[ ! "$proxy_port" =~ ^[1-9][0-9]{3,4}$ ]] || (( proxy_port < 1024 || proxy_port > 65535 )); then
        echo 'PROXY_PORT must be an integer between 1024 and 65535.' >&2
        exit 1
    fi
    proxy_url="http://127.0.0.1:$proxy_port"
}

check_proxy() {
    curl --proxy "$proxy_url" --noproxy '' --fail --silent --show-error \
        --connect-timeout 5 --max-time 20 --output /dev/null \
        https://www.cloudflare.com/cdn-cgi/trace
}

prepare_vpn_config() {
    if [[ ! -f "$1" || ! -r "$1" ]]; then
        echo 'VPN_CONFIG must point to a readable WireGuard file.' >&2
        exit 1
    fi
    # Gluetun v3.41 rejects IPv6 interface addresses when container IPv6 is disabled.
    if ! awk '
    /^[[:space:]]*Address[[:space:]]*=/ {
        sub(/^[^=]*=/, "")
        count = split($0, addresses, ",")
        result = ""
        for (i = 1; i <= count; i++) {
            gsub(/[[:space:]]/, "", addresses[i])
            if (addresses[i] != "" && addresses[i] !~ /:/)
                result = result (result == "" ? "" : ", ") addresses[i]
        }
        if (result == "") exit 1
        print "Address = " result
        address_lines++
        next
    }
    /^[[:space:]]*AllowedIPs[[:space:]]*=/ {
        value = $0
        sub(/^[^=]*=/, "", value)
        count = split(value, networks, ",")
        for (i = 1; i <= count; i++) {
            gsub(/[[:space:]]/, "", networks[i])
            if (networks[i] == "0.0.0.0/0") full_ipv4 = 1
        }
    }
    { print }
    END { if (address_lines != 1 || !full_ipv4) exit 1 }
    ' "$1" > "$2"; then
        echo 'WireGuard config must contain one IPv4 Address line and AllowedIPs covering 0.0.0.0/0.' >&2
        exit 1
    fi
}
