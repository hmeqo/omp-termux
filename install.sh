#!/bin/sh
set -eu

REPO="${OMP_TERMUX_REPO:-hmeqo/omp-termux}"                 # must match bin/omp-termux
raw="${OMP_TERMUX_RAW_BASE:-https://raw.githubusercontent.com/$REPO/main}"

die() { echo "install: error: $*" >&2; exit 1; }

# Prerequisites first: nothing is fetched or created before we know we can run the tool.
# Network: this script fetches the tool below and nothing else (the README Privacy section lists every
# endpoint the tool itself uses); no identifiers are sent, and there is no telemetry.
command -v bash >/dev/null 2>&1 || die "bash is required; run: pkg install bash"
command -v curl >/dev/null 2>&1 || die "curl is required; run: pkg install curl"
work="$(mktemp -d "${TMPDIR:-$HOME}/omp-termux-install.XXXXXX")" || die "cannot create a scratch directory"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

echo "==> fetching omp-termux"
curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "$raw/bin/omp-termux" -o "$work/bin/omp-termux" ||
	die "cannot fetch $raw/bin/omp-termux"
bash -n "$work/bin/omp-termux" || die "the downloaded omp-termux is not valid shell"
echo "==> omp-termux v$(sed -n 's/^TOOL_VERSION=\([^[:space:]]*\).*/\1/p' "$work/bin/omp-termux" | head -n1) ($(sha256sum "$work/bin/omp-termux" | cut -c1-12))"

# A bare `install` would only align the addon with the omp already on the device.
if [ "$#" -eq 0 ]; then
	set -- "${OMP_TERMUX_VERSION:-latest}"
fi

bash "$work/bin/omp-termux" install "$@"
