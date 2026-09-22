#!/bin/sh
# Fetches omp-termux and lets it install the addon matching the omp on this device.
set -eu

REPO="${OMP_TERMUX_REPO:-hmeqo/omp-termux}"                 # must match bin/omp-termux
raw="${OMP_TERMUX_RAW_BASE:-https://raw.githubusercontent.com/$REPO/main}"
work="${TMPDIR:-$HOME}/omp-termux-install.$$"               # ours alone; removed on exit

die() { echo "install: $*" >&2; exit 1; }

# Prerequisites first: nothing is fetched or created before we know we can run the tool.
command -v bash >/dev/null 2>&1 || die "bash is required; run: pkg install bash"
mkdir -p "$work/bin"
trap 'rm -rf "$work"' EXIT

echo "==> fetching omp-termux"
curl -fsSL "$raw/bin/omp-termux" -o "$work/bin/omp-termux" || die "cannot fetch $raw/bin/omp-termux"
bash -n "$work/bin/omp-termux" || die "the downloaded omp-termux is not valid shell"
echo "==> omp-termux v$(sed -n 's/^TOOL_VERSION=\([^[:space:]]*\).*/\1/p' "$work/bin/omp-termux" | head -n1) ($(sha256sum "$work/bin/omp-termux" | cut -c1-12))"

OMP_TERMUX_MODE=device bash "$work/bin/omp-termux" install
