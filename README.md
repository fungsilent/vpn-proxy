# VPN Proxy

A local HTTP proxy built with Gluetun, WireGuard, and Tinyproxy, allowing apps to share a VPN connection.

```text
Apps → 127.0.0.1:PROXY_PORT → Tinyproxy → WireGuard → Internet
```

## Requirements

- Linux with WireGuard support.
- Docker Engine and Docker Compose, with permission to access Docker.
- Bash, curl, flock, and pnpm.

## Setup and start

Run commands from the project root. On first use, create `.env`; edit it directly if it already exists:

```bash
cp .env.example .env
chmod 600 .env
```

Set the absolute path to your WireGuard configuration and the local proxy port:

```dotenv
VPN_CONFIG=/home/user/.config/vpn/proxy.conf
PROXY_PORT=40000
```

The WireGuard configuration must include an IPv4 Address and AllowedIPs covering `0.0.0.0/0`. Keep the configuration outside Git, and avoid using the same WireGuard key in multiple tunnels at once.

```bash
pnpm deploy:start
```

On success, the script prints the proxy address and configuration filename:

```text
VPN proxy ready at http://127.0.0.1:40000.
VPN config: proxy.conf
```

Check the exit IP:

```bash
curl --proxy http://127.0.0.1:40000 --noproxy '' \
  --fail --connect-timeout 5 --max-time 20 \
  https://www.cloudflare.com/cdn-cgi/trace
```

Compare the response's `ip` value with the expected VPN exit IP. If you change the port, replace `40000` in this command.

## Manage services

| Command | Action |
| --- | --- |
| `pnpm deploy:start` | Pull the VPN image, build the proxy image, recreate and start services, and verify connectivity |
| `pnpm deploy:stop` | Stop services while keeping containers |
| `pnpm deploy:down` | Remove service containers and the Compose network while keeping images and local configuration |
| `pnpm vpn:use <profile>` | Switch VPN profiles |
| `pnpm apps:codex` | Configure Codex to use the proxy |

If Docker Engine starts at boot, previously running containers restart automatically. After stopping services with `deploy:stop`, run `deploy:start` to start them again.

## Switch VPN profiles

Store profiles in `~/.config/vpn/`:

```text
~/.config/vpn/hk.conf
~/.config/vpn/jp.conf
```

While services are running, pass the filename without `.conf`:

```bash
pnpm vpn:use jp
```

```text
VPN profile jp is active at http://127.0.0.1:40000.
```

A successful switch updates `VPN_CONFIG` in `.env`; there is no need to run `deploy:start` again. The proxy address stays the same, so apps need no configuration changes. Existing connections are interrupted.

If switching fails, the script attempts to restore the previous VPN. If recovery also fails, it attempts to stop services and prints the location of the recovery files. Inspect those files and the Docker state before redeploying.

Profile names must start with a letter or number and may contain letters, numbers, `-`, and `_`. Keep exactly one single-line `VPN_CONFIG` assignment in `.env`. Do not export `VPN_CONFIG` in your shell or edit `.env` during a switch.

## Configure Codex

Ensure Codex is installed at `~/.local/bin/codex`, then run:

```bash
pnpm apps:codex
```

Setup writes proxy environment variables to `${CODEX_HOME:-$HOME/.codex}/.env`, preserves other settings, and creates a numbered backup before changing an existing file. Restart Codex and any running background app-server afterward.

## Apply configuration changes

| Change | Action |
| --- | --- |
| `VPN_CONFIG` in `.env`, or the original WireGuard configuration | Run `pnpm deploy:start` |
| `PROXY_PORT` in `.env` | Run `pnpm deploy:start`; if using Codex setup, also run `pnpm apps:codex` and restart Codex |
| Codex's `.env` | Restart Codex and its background app-server |

## Runtime data

| Path | Purpose |
| --- | --- |
| `.data/wireguard/wg0.conf` | WireGuard configuration copy mounted into Docker |
| `.data/deploy.lock` | Prevent concurrent deployments or switches |
| `.data/switch.*` | Temporary switch and recovery files; removed after normal completion |

`wg0.conf` contains the private key and has permissions `600`. Git ignores `.data/`. Keep this copy available for container recreation and boot recovery; do not delete it while the service is in use. Both `stop` and `down` preserve `.data/`.
