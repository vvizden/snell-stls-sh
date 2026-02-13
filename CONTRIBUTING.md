# Contributing

Thanks for contributing.

## Scope

- This repo focuses on a Debian/Ubuntu + systemd one-shot deployment script for Snell v5 + ShadowTLS v3.
- Avoid adding unrelated features that significantly expand the support matrix.

## Development Notes

- Please keep changes POSIX-ish where possible, but Bash is allowed/expected for this script.
- Keep output user-friendly and avoid printing secrets unless necessary.
- If you add new external endpoints (download sources, IP detection services, etc.), update `README.md` accordingly.

## Pull Requests

- Describe what problem is being solved and how it was tested.
- Include before/after snippets for user-facing output changes.
