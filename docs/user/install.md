# Install details

[English](install.md) | [中文](install.zh-CN.md)

The one-line installer from the [README](../../README.md) runs `install`. It:

1. installs bun if it is missing;
2. updates omp to the newest version built here;
3. copies the matching addon into the `native/` directory of the pi-natives package;
4. links `omp-termux` into `PATH`.

Arguments are passed through to `install`: `-s -- 18.3.4` at the end of the installer command installs version 18.3.4.

If `omp` or `omp-termux` is still not found afterwards, the script offers to add them to your shell's startup
file; accept and open a new terminal.

## Update checks

A newer `omp-termux` on `main` is reported on stderr on every run of `omp-termux` until you update it. Set
`OMP_TERMUX_NO_UPDATE_CHECK=1` to skip the check, or `OMP_TERMUX_UPDATE_TTL` (seconds, default 86400) to change
how often it queries. The check only requests `main` from GitHub; no telemetry or identifiers are sent.
