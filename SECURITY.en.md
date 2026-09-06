# Security feedback

[中文](SECURITY.md)

When reporting an issue, include your OS version, architecture, reproduction steps, and expected and actual results. Redact keys, passwords, public addresses and other sensitive information from logs or screenshots.

Configuration and connection keys are stored under `/opt/snellctl/generations/`. The `snellctl export` command prints the connection key, so keep its output private. `snellctl uninstall` permanently deletes this data.

This is a personal learning project. See the [README disclaimer](README.en.md#disclaimer).
