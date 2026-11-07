#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 1 || ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo 'Usage: pnpm vpn:use <profile>; reads ~/.config/vpn/<profile>.conf' >&2
    exit 1
fi
if [[ -v VPN_CONFIG ]]; then
    echo 'Unset exported VPN_CONFIG before switching; the selection is persisted in root .env.' >&2
    exit 1
fi
profile=$1
candidate="$HOME/.config/vpn/$profile.conf"
if [[ "$candidate" == *$'\n'* || "$candidate" == *$'\r'* ]]; then
    echo 'Profile paths must not contain newline characters.' >&2
    exit 1
fi
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
lock_deployment
load_config
docker info >/dev/null
running=$("${compose[@]}" ps --status running --services)
if ! grep -qx vpn <<< "$running" || ! grep -qx proxy <<< "$running"; then
    echo 'Both services must be running. Run deploy:start first.' >&2
    exit 1
fi
if [[ "$("${compose[@]}" port vpn 8888)" != "127.0.0.1:$proxy_port" ]]; then
    echo 'PROXY_PORT differs from the running service; apply port changes with deploy:start first.' >&2
    exit 1
fi
active="$repo_root/.data/wireguard/wg0.conf"
if [[ ! -f "$active" ]]; then
    echo 'The deployed WireGuard copy is missing. Run deploy:start first.' >&2
    exit 1
fi
tmp=$(mktemp -d "$repo_root/.data/switch.XXXXXX")
changed=0
env_changed=0
apply_vpn() {
    "${compose[@]}" up -d --force-recreate --no-build --pull never --wait --wait-timeout 120 && check_proxy
}
cleanup() {
    status=$?
    keep_backup=0
    trap - EXIT
    trap '' INT TERM
    if [[ "$changed" == 1 ]]; then
        echo 'Switch failed; restoring the previous VPN.' >&2
        if mv -- "$tmp/previous.conf" "$active" && \
           { [[ "$env_changed" == 0 ]] || mv -- "$tmp/previous.env" "$repo_root/.env"; } && \
           apply_vpn; then
            echo 'Previous VPN restored.' >&2
        else
            keep_backup=1
            echo 'Rollback failed; stopping VPN proxy services.' >&2
            printf 'Recovery files retained at %s.\n' "$tmp" >&2
            "${compose[@]}" stop || echo 'Could not stop services; inspect Docker state manually.' >&2
        fi
    fi
    if [[ "$keep_backup" == 0 ]]; then rm -rf -- "$tmp"; fi
    exit "$status"
}
# shortcut: recovery handles errors and INT/TERM; add startup recovery if power-loss guarantees are needed.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
prepare_vpn_config "$candidate" "$tmp/next.conf"
cp -p -- "$active" "$tmp/previous.conf"
cp -p -- "$repo_root/.env" "$tmp/previous.env"
# shortcut: VPN_CONFIG must be one single-line assignment; use a dotenv-aware editor if multiline values are needed.
mapfile -t definitions < <(grep -E '^[[:space:]]*(export[[:space:]]+)?VPN_CONFIG[[:space:]]*=' "$repo_root/.env")
if [[ ${#definitions[@]} != 1 ]]; then
    echo '.env must contain exactly one VPN_CONFIG assignment.' >&2
    exit 1
fi
value=${definitions[0]#*=}
value=${value#"${value%%[![:space:]]*}"}
double_quoted='^"([^"\\]|\\.)*"[[:space:]]*(#.*)?$'
single_quoted="^'([^'\\\\]|\\\\.)*'[[:space:]]*(#.*)?$"
if [[ ( "$value" == \"* && ! "$value" =~ $double_quoted ) || \
      ( "$value" == \'* && ! "$value" =~ $single_quoted ) ]]; then
    echo 'VPN_CONFIG must use a single-line dotenv value.' >&2
    exit 1
fi
awk '!/^[[:space:]]*(export[[:space:]]+)?VPN_CONFIG[[:space:]]*=/' "$repo_root/.env" > "$tmp/next.env"
quoted=${candidate//\\/\\\\}
quoted=${quoted//\"/\\\"}
quoted=${quoted//\$/\$\$}
printf 'VPN_CONFIG="%s"\n' "$quoted" >> "$tmp/next.env"
docker compose --project-directory "$repo_root" --env-file "$tmp/next.env" \
    -f "$repo_root/deploy/compose.yaml" config --quiet
changed=1
mv -- "$tmp/next.conf" "$active"
if ! apply_vpn; then
    exit 1
fi
if ! cmp -s "$repo_root/.env" "$tmp/previous.env"; then
    echo '.env changed during the switch; refusing to overwrite it.' >&2
    exit 1
fi
env_changed=1
mv -- "$tmp/next.env" "$repo_root/.env"
changed=0
printf 'VPN profile %s is active at %s.\n' "$profile" "$proxy_url"
