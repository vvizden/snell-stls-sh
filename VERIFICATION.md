# Verification record

Date: 2026-09-05. This is a development verification record, not a claim that every supported future release has been tested.

## Discovery and support

- Official release page discovered **5.0.1** for stable and **6.0.0rc2** for both rc and beta. The page is a discoverable subset, not a historical index.
- Exact official **6.0.0b4** archives remained downloadable during testing.
- The manager accepts protocol majors **5 and 6**, including their new Beta/RC/final releases. Unknown majors require a management-tool update.
- Official 6.0.0rc2/aarch64 reports `snell-server v6.0.0 (Aug 7 2026)`. The manager records both the complete artifact label and this reduced binary report, with source URL and hashes. It accepts this base-only report for prereleases but rejects another base version or a conflicting suffix.
- The tested archives had no sibling `.zip.sha256` checksum; metadata correctly records `local-only`. The recorded hash is an integrity baseline, not an upstream signature.

Sources: [official releases](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell), [official protocol parameters](https://manual.nssurge.com/policies/snell.html).

## Automated checks

- Bash syntax: passed.
- ShellCheck for the distributed `snell.sh`: passed.
- Portable test groups on macOS: 6 passed.
- Linux/root test groups in Debian 12: 14 passed. These cover numeric version ordering, original RC suffix regression, discovery fallback, channel ceilings, missing architectures, input validation, compatible config generation, full-snapshot transactions, failed recovery retention, ownership/integrity, locks, checksum handling and staging failures.

## Real service tests

Docker Desktop on an ARM Mac, privileged disposable Linux containers with systemd as PID 1:

| OS / architecture | Versions exercised | Result |
| --- | --- | --- |
| Debian 12 / aarch64 | 5.0.1, 6.0.0rc2, 6.0.0b4 | Full systemd acceptance suite passed |
| Ubuntu 24.04.4 / aarch64 | 5.0.1, 6.0.0rc2, 6.0.0b4 | Full systemd acceptance suite passed |
| Debian 12 / amd64 under ARM emulation | 5.0.1 | **Blocked**: official binary segfaults even on standalone `--version`, as root and as snell; staging rejects it before activation |

The amd64 result does not establish whether native amd64 works or fails. A native amd64 host is still required for release acceptance. Native host/VM boot, power loss, other OS releases and long-running operation remain unverified.

## Surge client tests

Surge Mac **6.9.0 (12250)** against the Debian/aarch64 container through a loopback TCP port mapping:

- **6.0.0rc2**: exported configuration validation passed; three HTTPS HEAD probes returned HTTP 200; the server showed the same established Snell TCP four-tuple after all three probes; UDP policy probe succeeded (2 ms).
- **5.0.1 after rollback**: restored export validated; three HTTPS HEAD probes returned HTTP 200 using the same observed Snell TCP connection; UDP policy probe succeeded (1 ms).
- The test policy was temporary and removed afterwards; the original profile was restored and reloaded.
- These checks establish local client interoperability and observed reuse for the tested requests. They do not establish public ingress reachability, production reliability, real-time UDP performance or Surge iOS compatibility.

See [tests/README.md](tests/README.md) for reproduction and required remaining acceptance.
