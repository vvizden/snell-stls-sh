# snellctl

[中文](README.md)

A lightweight Snell server manager built with Bash and systemd. Supports Snell 5.x / 6.x stable, RC, Beta and specific versions, with installation, upgrades, rollback and Surge configuration export.

## Disclaimer

This is a personal learning project, shared for educational purposes and provided as is. Assess the risks before use and follow applicable laws and your service provider's terms. The author accepts no liability for losses arising from its use.

## Install

Use a Debian or Ubuntu server running systemd on amd64 or aarch64, with root or sudo access. This tool is for fresh installations; manually remove any existing Snell deployment first.

Connect to your server over SSH, download and inspect the script, then run the installer. If you log in as root, omit `sudo` from the commands.

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates
curl -fsSL -o snell.sh https://raw.githubusercontent.com/vvizden/snellctl/main/snell.sh
sudo bash snell.sh install
```

Follow the prompts:

| Setting | What to enter |
| --- | --- |
| Public address | Your server's public IPv4 address, or a domain that resolves to it |
| Port | The default is `443`; you can choose another available port |
| Channel | Use the default `stable` channel for regular use |

The script prepares the remaining dependencies and generates a connection key. After installation, allow the selected **TCP port** in your server firewall and cloud security group. Keep the downloaded `snell.sh` for removing installation data later.

## Add to Surge

Run on your server:

```bash
sudo snellctl export
```

Copy the output line into the `[Proxy]` section of your Surge profile. Save the profile, select the new proxy and test a request. The exported line contains your connection key; keep it private.

## Everyday commands

Run these commands on your server:

| Task | Command |
| --- | --- |
| Check service status | `sudo snellctl status` |
| List available versions | `snellctl versions` |
| Upgrade to the latest version in your channel | `sudo snellctl upgrade` |
| Restore the previous deployment | `sudo snellctl rollback` |
| Export the current Surge configuration | `sudo snellctl export` |
| Read recent logs | `sudo journalctl -u snell-server.service -n 50` |

Upgrades preserve your connection key and briefly interrupt connections. If the new version fails startup checks, the tool attempts to restore the previous deployment. Test with Surge after upgrading. To recover, run `rollback`, then export the restored configuration and update your client.

## Choose a version

When you run an upgrade, the tool selects the latest version in your channel from the [official release page](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell).

| Channel | Candidates |
| --- | --- |
| `stable` | Final releases, recommended for regular use |
| `rc` | Final releases and release candidates |
| `beta` | Final releases, release candidates and Beta releases |

For example, switch to the RC channel:

```bash
sudo snellctl upgrade --channel rc
```

The Beta channel follows later RC and final releases too. Before using a prerelease, check that your Surge client supports it.

To select a specific version, use `--version` in place of `--channel`. Add `--allow-downgrade` when moving to an older version, for example:

```bash
sudo snellctl upgrade --version 5.0.1 --allow-downgrade
```

Installing a specific version saves its matching channel. Selecting a specific version during an upgrade preserves your saved channel. See `snellctl --help` for all options.

## Uninstall

Remove the service and management command while keeping configuration and rollback data:

```bash
sudo snellctl uninstall
```

To delete configuration, keys and rollback data completely, use the script saved during installation:

```bash
sudo bash snell.sh uninstall --purge
```

Complete the full removal before installing again.

## Development and feedback

[Contributing](CONTRIBUTING.en.md) · [Testing](tests/README.en.md) · [Verification record](VERIFICATION.en.md) · [Security feedback](SECURITY.en.md)
