# snell-stls-sh: Snell v5 + ShadowTLS v3 Deploy Script (Debian/Ubuntu + systemd)

Language: [Chinese](README.md) | [English](README.en.md)

## Disclaimer

- This project is for learning and communication only. Do not use it for illegal purposes.
- This project does not guarantee availability/security/maintainability and you must evaluate and be responsible for it yourself.
- The script downloads and installs third-party software (Snell / ShadowTLS). Verify sources and licenses yourself and make sure you comply with local laws and provider terms.

## Quick Start

You need:

- A Debian/Ubuntu VPS (must have `systemd`)
- An account that can log in (commonly `root`)
- `ssh` on your local machine
- The VPS must be able to reach GitHub (outbound network works) and have `curl` installed

Placeholder notes:

- `<VPS_IP>`: your VPS public IP
- `<SSH_PORT>`: SSH port (default `22`)
- `<PRIVATE_KEY_PATH>`: path to your private key (only needed if it is not in the default location)

### Option A: SSH key login (recommended)

1) SSH into the VPS:

```bash
ssh root@<VPS_IP>
```

If your private key is not in the default location, add `-i <PRIVATE_KEY_PATH>`:

```bash
ssh -i <PRIVATE_KEY_PATH> root@<VPS_IP>
```

If your SSH port is not 22, add `-p <SSH_PORT>`:

```bash
ssh -p <SSH_PORT> root@<VPS_IP>
```

2) Download the script from GitHub on the VPS (downloads the latest `main` by default):

```bash
apt-get update
apt-get install -y curl ca-certificates
curl -fsSL -o /root/deploy_snell_stls.sh https://raw.githubusercontent.com/vvizden/snell-stls-sh/main/deploy_snell_stls.sh
chmod +x /root/deploy_snell_stls.sh
```

Tip: if you want to pin a specific version, replace `main` in the URL with a commit hash.

3) Run unattended install:

```bash
bash /root/deploy_snell_stls.sh install --non-interactive --yes
```

If you are not logged in as `root`, use `sudo`:

```bash
sudo bash /root/deploy_snell_stls.sh install --non-interactive --yes
```

### Option B: Password login

1) SSH into the VPS:

```bash
ssh root@<VPS_IP>
```

If your SSH port is not 22, add `-p <SSH_PORT>`:

```bash
ssh -p <SSH_PORT> root@<VPS_IP>
```

If your machine tries too many SSH keys before prompting for password, force password auth:

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no root@<VPS_IP>
```

If your SSH port is not 22 and you need to force password auth:

```bash
ssh -p <SSH_PORT> -o PreferredAuthentications=password -o PubkeyAuthentication=no root@<VPS_IP>
```

2) Download the script from GitHub on the VPS:

```bash
apt-get update
apt-get install -y curl ca-certificates
curl -fsSL -o /root/deploy_snell_stls.sh https://raw.githubusercontent.com/vvizden/snell-stls-sh/main/deploy_snell_stls.sh
chmod +x /root/deploy_snell_stls.sh
```

3) Run unattended install:

```bash
bash /root/deploy_snell_stls.sh install --non-interactive --yes
```

## Getting the Surge config

After a successful deployment:

- The script prints a Surge `[Proxy]` line directly in the terminal.
- It also writes copy-paste friendly files on the server:
  - `/root/snell-surge-proxy.conf`
  - `/root/snell-stls-info.txt`

Treat them as secrets: they contain Snell PSK / ShadowTLS password.

## What the script does (short)

- Installs `snell-server` and `shadow-tls` binaries and registers `systemd` services
- `snell-server` listens only on loopback: `127.0.0.1:<snell-port>` (default `18080`)
- `shadow-tls` listens on public entry: `0.0.0.0:<public-port>` (default `443/tcp`)
- Key files created/modified:
  - `/etc/snell/snell-server.conf`
  - `/etc/systemd/system/snell-server.service`
  - `/etc/systemd/system/shadow-tls.service`
  - `/usr/local/bin/snell-server`
  - `/usr/local/bin/shadow-tls`
  - `/root/snell-surge-proxy.conf`
  - `/root/snell-stls-info.txt`

## Common commands

```bash
# interactive install
bash /root/deploy_snell_stls.sh install

# upgrade (tries to keep ports/keys/SNI)
bash /root/deploy_snell_stls.sh upgrade --yes

# status (services/ports/recent logs)
bash /root/deploy_snell_stls.sh status

# uninstall (keeps connection info files)
bash /root/deploy_snell_stls.sh uninstall --yes

# uninstall and delete connection info files
bash /root/deploy_snell_stls.sh uninstall --purge --yes
```

## Flags (quick reference)

| Flag | Meaning | Default | When to change |
| --- | --- | --- | --- |
| `--public-port <port>` | public entry port | `443` | 443 is taken or you prefer another port |
| `--snell-port <port>` | Snell local port (loopback) | `18080` | conflict with existing services |
| `--snell-psk <value>` | Snell PSK | auto-generated | unify config across machines or keep it fixed |
| `--stls-password <value>` | ShadowTLS password | auto-generated | same as above |
| `--stls-sni <domain>` | ShadowTLS SNI domain | auto-picked | auto-pick failed or you want to pin a domain |
| `--ssh-port <port>` | SSH port kept open by firewall | auto-detect (fallback `22`) | auto-detect got it wrong |
| `--no-firewall` | do not change firewall | off | you manage firewall yourself |
| `--non-interactive` | no prompts | off | automation/batch runs |
| `--yes` | skip confirmation | off | automation |

For full help:

```bash
bash /root/deploy_snell_stls.sh --help
```

## Troubleshooting

### 1) Snell download failed (possible anti-bot / captcha)

The script parses Surge Snell release notes to locate Linux download links. If the VPS egress is blocked or the page format changes, it may fail and dump the raw page to:

```bash
sed -n '1,80p' /tmp/snell_release_notes_last.html
```

### 2) Service is not active

Use:

```bash
bash /root/deploy_snell_stls.sh status
```

### 3) Your `--stls-sni` is rejected

The script probes TLS 1.3 support via `openssl s_client -tls1_3`. If the domain does not complete a TLS 1.3 handshake from the server network, the script fails. Use a well-known TLS 1.3 domain or omit `--stls-sni` to let it auto-pick.

## References

- Surge KB (Snell release notes): <https://kb.nssurge.com/surge-knowledge-base/release-notes/snell>
- ShadowTLS: <https://github.com/ihciah/shadow-tls>
