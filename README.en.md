# snellctl: native Snell, one instance

[中文](README.md)

A standalone Bash + systemd manager for Snell 5.x/6.x final, RC, beta and exact releases. Fresh installations, one service, complete snapshots and offline rollback. No ShadowTLS, SNI, migration, background updater, kernel tuning or firewall changes.

## Install

Requires Debian/Ubuntu with running systemd, root/sudo, amd64/aarch64. Missing packages (curl, CA certificates, unzip, jq, file, OpenSSL, util-linux, iproute2 and coreutils) are installed via apt.

Download and inspect on your VPS:

```bash
curl -fsSL -o snell.sh https://raw.githubusercontent.com/vvizden/snellctl/main/snell.sh
sudo bash snell.sh install
# Automation: replace the example with your public IPv4 address or DNS name.
sudo bash snell.sh install --server vpn.example.com --channel stable --non-interactive --yes
sudo snellctl status
sudo snellctl export
```

Interactive setup asks for the public address, port (443) and channel (stable). Pin the download URL to a reviewed commit instead of main for reproducibility. Existing foreign files/services/accounts and occupied ports are rejected, not adopted or stopped. Remove legacy installations manually. Keep the downloaded script to purge retained data after uninstalling the command.

export prints a Surge [Proxy] declaration containing the PSK. Do not share it in logs, screenshots or issues. Open the selected **TCP** port in the host firewall/provider security group yourself; SSH rules are never changed.

## Releases

| Channel | Allowed maturity |
| --- | --- |
| stable | Final |
| rc | Final + RC |
| beta | Final + RC + beta |

Compare base versions first, then maturity and numeric sequence: `6.0.0b4 < 6.0.0rc < 6.0.0rc2 < 6.0.0 < 6.1.0b1`. Unnumbered rc sorts as rc1 while preserving the original filename. A beta ceiling naturally follows RC and final releases.

```bash
snellctl versions
sudo snellctl upgrade --yes
sudo snellctl upgrade --channel rc --yes
sudo snellctl upgrade --channel beta --yes
sudo snellctl upgrade --version 6.0.0b4 --allow-downgrade --yes
sudo snellctl rollback --yes
sudo snellctl status
sudo snellctl export
```

--channel and --version are mutually exclusive. Exact fresh installs save the release's maturity as their channel; exact upgrades preserve the saved channel. Downgrades require upgrade --version plus --allow-downgrade; changing channels never silently downgrades. Offline rollback restores the previous complete snapshot including its channel. Another rollback switches back.

The official Markdown release page is queried live, with same-page HTML fallback. versions lists discoverable releases and readable local snapshots, not a complete historical archive. Exact versions validate the corresponding official file, without guessed fallback versions or third-party mirrors. When release notes lag, an explicitly supplied --version can select a known available file.

Selection determines the latest candidate before checking architecture availability; absent builds stop the operation instead of selecting older versions. Unknown formats stop discovery; unknown protocol majors require a manager update. New releases within 5.x/6.x need no individual allowlist. upgrade updates the server, not the management script.

## Runtime and recovery

- IPv4 listener 0.0.0.0:443, IPv4 egress, system DNS. Install-only --port changes the port.
- PSK defaults to 32 random bytes rendered as 64 hexadecimal characters. Install-only --psk accepts 16–255 ASCII letters/digits/underscore/hyphen. Upgrades retain it; ordinary output omits secrets.
- Surge uses version=5 for 5.x and version=6 for 6.x, reuse=true and block-quic=on; TFO is not enabled. v6 retains built-in default encryption/shaping, without unsafe-raw or new configuration fields injected into early betas.
- Ordinary UDP travels through Snell's TCP transport; QUIC is blocked in the export. No public UDP port is required. TCP still affects real-time UDP performance.
- snell-server.service runs as the dedicated snell account with only CAP_NET_BIND_SERVICE, not root.
- /usr/local/sbin/snellctl is the installed command; /opt/snellctl/generations/ contains complete snapshots, selected by an atomic current symlink.
- Snapshots contain the binary, server configuration, Surge snippet and metadata. Server secrets are root/service-readable, export/metadata root-only. Manual snapshot changes fail integrity checks.
- Downloads stay under the official dl.nssurge.com/snell/ directory. An official sibling .sha256 file is verified when available; 404/410 records local-only. Local hashes detect later changes, not source authenticity. Source authentication relies on HTTPS.

Downloads, ZIP checks, architecture and executable checks precede stopping the old service. A transaction records the old state. After switching, the same target PID must be active and own the expected listener for five consecutive samples (about four seconds), within approximately fifteen seconds. Failure restores the complete previous snapshot and returns an error. Only current and previous snapshots are retained.

Ordinary exits/signals attempt recovery. After forced termination or power loss, the next privileged management operation recovers or reports the blocker; unsuccessful recovery retains the transaction. systemd boots the currently selected complete snapshot, without treating an unfinished update as accepted. Single-instance upgrades briefly disconnect existing requests.

**Local startup checks do not verify public reachability, destination access or Surge compatibility.** Beta changes may require a matching client update. Test HTTPS, connection reuse and ordinary UDP from Surge; use offline rollback and the previous export if necessary. Review journal logs before sharing them.

## Uninstall

```bash
sudo journalctl -u snell-server.service -n 50
sudo snellctl uninstall --yes
# The installed command is now removed:
sudo bash snell.sh uninstall --purge --yes
```

Default uninstall removes the service/command and retains snapshots, credentials and account. --purge removes retained data too. Purge before a fresh reinstall. Unexpected files, ownership/account changes or external systemd overrides require manual inspection.

## Verification

Official discovery, supported protocol range and actually tested platforms/versions are separate facts.

```bash
bash -n snell.sh
bash tests/run.sh
docker build -f tests/Dockerfile -t snellctl-test .
docker run --rm snellctl-test
```

See [tests/README.md](tests/README.md) for isolated real-systemd acceptance and [VERIFICATION.md](VERIFICATION.md) for actual coverage. Mocks and syntax checks do not prove real deployment or Surge connectivity.

## Sources

- [Official releases and security trade-offs](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- [Surge Snell parameters](https://manual.nssurge.com/policies/snell.html)
- [Introducing Snell v6](https://nssurge.com/blog/snell-v6/)

Snell does not provide forward secrecy. This tool does not change protocol security properties or guarantee availability/censorship resistance. Third-party binaries and this project are provided as-is.
