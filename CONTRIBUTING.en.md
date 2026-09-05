# Contributing

[中文](CONTRIBUTING.md)

The project uses Bash and systemd to manage Snell 5.x / 6.x on Debian / Ubuntu, supporting amd64 and aarch64.

## Changes

- Keep `snell.sh` standalone and safe to source for testing.
- Preserve full version numbers and Beta / RC suffixes. Record the installed version and client protocol version separately.
- Use ownership markers to identify managed files. Upgrades and rollbacks must switch the binary, server configuration, client configuration and channel together.
- Keep key output in the `export` command.
- Update both language versions of the documentation when features or usage change.

## Verification and submissions

Follow the [testing guide](tests/README.en.md) for syntax checks, ShellCheck and tests. Deployment changes also need real systemd and Surge verification. Record the environment, versions and results in the [verification record](VERIFICATION.en.md).

Describe the problem, any changes to usage and the verification results in your submission.
