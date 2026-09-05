# Security Policy

## Reporting a Vulnerability

If you believe you found a security issue in this project, please open a GitHub issue with minimal sensitive details, and include:

- What you were trying to do
- Reproduction steps (redact IPs/keys/passwords/tokens)
- Expected vs actual behavior
- OS version / distro (Debian/Ubuntu) and architecture

Notes:

- This project is provided "as is" without warranty.
- Snell PSKs reside under `/opt/snellctl/generations/` in root/service-readable server configs and root-only Surge exports. Default uninstall retains credentials; `uninstall --purge` removes managed snapshots.
- `snellctl export` intentionally prints the PSK. Ordinary command output must omit secrets. Review journal output before sharing it.
- The tool manages marked installations and downloads official HTTPS artifacts. Local hashes detect later modification; they are not upstream signatures.
- Snell does not provide forward secrecy. Beta/RC client compatibility and public reachability are separate from local startup checks.
