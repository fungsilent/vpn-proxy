#!/usr/bin/env bash
set -euo pipefail
if (( $# )); then
    echo 'Usage: bash apps/codex/setup.sh' >&2
    exit 1
fi
repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repo_root/deploy/script/common.sh"
load_config
if [[ ! -x "$HOME/.local/bin/codex" ]]; then
    echo 'Install Codex at ~/.local/bin/codex before configuring its proxy.' >&2
    exit 1
fi
umask 077
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
codex_home=${CODEX_HOME:-$HOME/.codex}
mkdir -p -m 700 "$codex_home"
target="$codex_home/.env"
mode=600
if [[ -e "$target" ]]; then
    if ! awk '
    $0 == "# BEGIN vpn-proxy" { if (inside || seen++) exit 1; inside = 1; next }
    $0 == "# END vpn-proxy" { if (!inside) exit 1; inside = 0; next }
    !inside { print }
    END { if (inside) exit 1 }
    ' "$target" > "$tmp/settings"; then
        echo 'Invalid vpn-proxy block in Codex .env; file was not modified.' >&2
        exit 1
    fi
fi
cat >> "$tmp/settings" <<ENV
# BEGIN vpn-proxy
HTTP_PROXY=$proxy_url
HTTPS_PROXY=$proxy_url
ALL_PROXY=$proxy_url
WS_PROXY=$proxy_url
WSS_PROXY=$proxy_url
http_proxy=$proxy_url
https_proxy=$proxy_url
all_proxy=$proxy_url
ws_proxy=$proxy_url
wss_proxy=$proxy_url
NO_PROXY=localhost,127.0.0.1,::1
no_proxy=localhost,127.0.0.1,::1
# END vpn-proxy
ENV
if ! cmp -s "$tmp/settings" "$target"; then
    install --backup=numbered -m "$mode" "$tmp/settings" "$target"
fi
# Remove only the legacy function installed by this project's earlier setup.
if [[ -f "$HOME/.zshrc" ]]; then
    if awk '
    { lines[NR] = $0 }
    END {
        for (i = 1; i <= NR; i++) {
            if (lines[i] == "codex() {" &&
                lines[i+1] == "    \"$HOME/.local/bin/codex-proxy\" \"$@\"" && lines[i+2] == "}") {
                i += 2; found = 1; continue
            }
            print lines[i]
        }
        if (!found) exit 1
    }
    ' "$HOME/.zshrc" > "$tmp/zshrc"; then
        install --backup=numbered -m "$(stat -c %a "$HOME/.zshrc")" "$tmp/zshrc" "$HOME/.zshrc"
    fi
fi
printf 'codex proxy configured for %s.\n' "$proxy_url"
echo 'Codex reads its .env natively. Open a new terminal and restart existing Codex app-servers to apply.'
