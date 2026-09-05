# Contributing

Thanks for contributing.

## Scope

- Maintain a standalone Bash manager (`snell.sh`, installed as `snellctl`) for native Snell 5.x/6.x on Debian/Ubuntu + systemd, amd64/aarch64.
- One instance, maturity-ceiling channels, full-snapshot rollback. No ShadowTLS, legacy migration, background updates or firewall/kernel tuning.
- Avoid adding unrelated features that significantly expand the support matrix.

## Development Notes

- Please keep changes POSIX-ish where possible, but Bash is allowed/expected for this script.
- Keep output user-friendly and avoid printing secrets unless necessary.
- If you add new external endpoints (download sources, IP detection services, etc.), update `README.md` accordingly.
- Preserve full release suffixes; binary version and client protocol version are distinct.
- Only mutate marked installations. Binary, server config, client export and channel must switch and roll back together. Never print PSKs outside explicit `export`.
- Keep the entrypoint standalone and safe to source without invoking `main`.

## Verification

- Run `bash -n snell.sh` and `bash tests/run.sh`.
- Full Linux/root tests: `docker build -f tests/Dockerfile -t snellctl-test .` then `docker run --rm snellctl-test`.
- Deployment changes also require real-systemd acceptance from `tests/README.md`. Record OS, architecture, binary versions and test layers in `VERIFICATION.md`; mocks do not prove real deployment or client connectivity.
- Parser tests use fixtures; live official discovery is a separate smoke check.
- The reviewed script is the installed artifact. Check installed `snellctl --help` and commands as well as sourced functions. No generated distribution is needed.

## Pull Requests

- Describe what problem is being solved and how it was tested.
- Include before/after snippets for user-facing output changes.
