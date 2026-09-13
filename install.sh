#!/bin/sh
# Fetches omp-termux and lets it install the addon matching the omp on this device.
set -eu

REPO="${OMP_TERMUX_REPO:-hmeqo/omp-termux}"
raw="${OMP_TERMUX_RAW_BASE:-https://raw.githubusercontent.com/$REPO/main}"
work="${TMPDIR:-$HOME}/omp-termux-install.$$"

mkdir -p "$work/bin"
trap 'rm -rf "$work"' EXIT

echo "==> fetching omp-termux"
curl -fsSL "$raw/bin/omp-termux" -o "$work/bin/omp-termux" ||
	{ echo "install: cannot fetch $raw/bin/omp-termux" >&2; exit 1; }
command -v bash >/dev/null 2>&1 || { echo "install: bash is required; run: pkg install bash" >&2; exit 1; }
bash -n "$work/bin/omp-termux" || { echo "install: the downloaded omp-termux is not valid shell" >&2; exit 1; }

OMP_TERMUX_MODE=device bash "$work/bin/omp-termux" install
