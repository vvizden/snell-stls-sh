# Security Policy

## Reporting a Vulnerability

If you believe you found a security issue in this project, please open a GitHub issue with minimal sensitive details, and include:

- What you were trying to do
- Reproduction steps (redact IPs/keys/passwords/tokens)
- Expected vs actual behavior
- OS version / distro (Debian/Ubuntu) and architecture

Notes:

- This project is provided "as is" without warranty.
- The deployment script generates credentials (Snell PSK / ShadowTLS password) and writes them to `/root/snell-stls-info.txt` and `/root/snell-surge-proxy.conf` on the server. Treat these files as secrets and avoid sharing screenshots/logs containing them.
