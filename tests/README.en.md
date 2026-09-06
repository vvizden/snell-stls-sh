# Testing

[中文](README.md)

Run from the repository root. Test results and remaining coverage gaps are recorded in [VERIFICATION.md](../VERIFICATION.en.md).

## Syntax, parser and transaction tests

```bash
bash -n snell.sh
bash tests/run.sh
docker build -f tests/Dockerfile -t snellctl-test .
docker run --rm snellctl-test bash -c 'shellcheck snell.sh && bash tests/run.sh'
```

macOS runs six portable groups. The Linux/root container runs all fifteen groups, including real ownership, file hashes, symlink switching, locks and manager self-update. These tests mock systemd and network responses. Use the acceptance steps below to verify the server and Surge together.

## Real systemd acceptance

**Use a disposable container only.** The suite installs packages/accounts/services and purges its deployment. Do not run it on a production machine. Privileged containers should run on a dedicated test host/VM. These commands use real upstream downloads and can fail when upstream or network access changes.

```bash
docker build --build-arg DISTRO=debian:12 -f tests/systemd.Dockerfile -t snellctl-systemd-test .
docker run -d --name snellctl-acceptance --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock snellctl-systemd-test
docker exec -e SNELLCTL_DISPOSABLE_TEST=YES snellctl-acceptance bash /src/tests/systemd-acceptance.sh
docker rm -f snellctl-acceptance
```

Repeat with `DISTRO=ubuntu:24.04` and on native amd64/aarch64 hosts. Docker's arm64 platform corresponds to Snell's aarch64 artifact. On an ARM Mac, `--platform linux/amd64` uses emulation and cannot substitute for native amd64 acceptance. The script deliberately pins the 5.0.1 → 6.0.0rc2 → 6.0.0b4 regression sequence; update its expectations when the live RC channel moves.

The suite verifies occupied-port refusal, fresh install, permissions, channel selection, explicit downgrade, PSK preservation, offline rollback, real startup-failure recovery, SIGTERM cleanup, a simulated unfinished transaction, service restart, default uninstall, refusal to reinstall over retained data, and purge. Fault injection is confined to the test script. A daemon restart is tested; a full VM reboot and power-loss durability require separate VM acceptance.

## Surge acceptance

Use a separate disposable server/container and publish its TCP port to a reachable address. Install a desired version, obtain `snellctl export` privately, and put the line into a temporary Surge test policy. For a container port mapping, replace the exported server/port with the published endpoint. Validate the profile with `surge-cli --check <profile>` before reloading it.

After the policy becomes available:

```bash
surge-cli http probe https://www.apple.com/library/test/success.html snellctl-acceptance
surge-cli test-policy-udp snellctl-acceptance
```

Repeat HTTPS probes and inspect the server's `ss -Htn 'sport = :443'` output to establish whether the same Snell TCP connection is retained. Repeat after rollback, using the restored client export. Remove the temporary policy and reload/verify the original profile. Do not commit exports or PSKs. Public reachability, production routing, throughput and iOS compatibility require separate testing.
