#!/bin/sh
# Local verification: static gates, then the device-side paths against a fake device.
#
#   sh tests/verify.sh
#
# The device sections need out/pi_natives.android-arm64.node (run `./dev/omp-termux-dev build <version>` first);
# without it they are skipped. Nothing here touches a real device or the network: bun/curl are stubbed,
# HOME/TMPDIR/XDG_CONFIG_HOME are isolated, and device mode is forced with TERMUX_VERSION. Every path that may
# be removed is a hard-coded /tmp path and asserted below.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
[ -n "$R" ] && [ -f "$R/bin/omp-termux" ] || { echo "verify: cannot locate the repository; refusing to run" >&2; exit 1; }
fail=0
ok() { printf '  ok   %s\n' "$1"; }
no() { printf '  FAIL %s\n' "$1"; fail=1; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got [$2] want [$3])"; fi; }
nonzero() { [ "$1" -ne 0 ] && echo non0 || echo zero; }

echo "== static gates"
bash -n "$R/bin/omp-termux" && ok "bash -n bin/omp-termux" || no "bash -n bin/omp-termux"
bash -n "$R/dev/omp-termux-dev" && ok "bash -n dev/omp-termux-dev" || no "bash -n dev/omp-termux-dev"
sh -n "$R/install.sh" && ok "sh -n install.sh" || no "sh -n install.sh"
python3 -c "import yaml,pathlib;yaml.safe_load(pathlib.Path('$R/.github/workflows/build.yml').read_text())" 2>/dev/null &&
	ok "CI YAML parses" || no "CI YAML does not parse"
bash "$R/bin/omp-termux" bogus >/dev/null 2>&1; chk "unknown verb exits 1" "$?" "1"
bash "$R/bin/omp-termux" install --help >/dev/null 2>&1; chk "install --help refused" "$?" "1"
bash "$R/bin/omp-termux" verify --help >/dev/null 2>&1; chk "verify --help refused" "$?" "1"

if [ ! -f "$R/out/pi_natives.android-arm64.node" ]; then
	echo "== skipping the device sections (no out/pi_natives.android-arm64.node; run ./dev/omp-termux-dev build <version> first)"
	echo
	echo "failures: $fail"
	exit $fail
fi

REAL_CURL="$(command -v curl || true)"
REAL_SH="$(command -v sh || true)"
[ -n "$REAL_SH" ] || { echo "verify: sh is required" >&2; exit 1; }
[ -n "$REAL_CURL" ] || { echo "verify: curl is required" >&2; exit 1; }
REAL_BUN="$(command -v bun || true)"

# The fixtures follow the artifact in out/: the release it reports must equal the package version it is
# installed into, and the bumped versions keep the digit count so that release can be rewritten in place.
ART="$R/out/pi_natives.android-arm64.node"
V0="$(grep -ao 'PI_NATIVES_VERSION_STAMP:[-0-9A-Za-z._]*' "$ART" | head -1 | sed 's/^PI_NATIVES_VERSION_STAMP://')"
ID="PI_NATIVES_VERSION_STAMP:"
if [ -z "$V0" ]; then
	ID="__piNativesV"
	V0="$(grep -ao '__piNativesV[0-9A-Za-z_]*' "$ART" | head -1 | sed 's/^__piNativesV//; s/_/./g')"
fi
[ -n "$V0" ] || { echo "verify: out/pi_natives.android-arm64.node reports no release" >&2; exit 1; }
bump_version() { # $1 = version, $2 = how many releases ahead of it
	local major minor patch n
	major="${1%%.*}"; minor="${1#*.}"; minor="${minor%%.*}"; patch="${1##*.}"
	n=$((patch + $2))
	while [ "$n" -gt 9 ]; do minor=$((minor + 1)); n=$((n - 10)); done
	printf '%s.%s.%s' "$major" "$minor" "$n"
}
V1="$(bump_version "$V0" 1)"; V2="$(bump_version "$V0" 2)"
release_id() { # $1 = version -> the byte string the artifact records it in
	if [ "$ID" = "__piNativesV" ]; then
		printf '__piNativesV%s' "$(printf '%s' "$1" | tr . _)"
	else
		printf 'PI_NATIVES_VERSION_STAMP:%s' "$1"
	fi
}
S0="$(release_id "$V0")"
S1="$(release_id "$V1")"
S2="$(release_id "$V2")"

pkg_json() { printf '{"name":"@oh-my-pi/pi-natives","version":"%s"}' "$1"; }

# $1 = where to write it, $2 = the newest upstream release it answers, $3 = this repository's release
fake_curl() {
	{
		printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"/tmp/v-curl.log"\ncase "$*" in\n'
		printf '*github.com/can1357/oh-my-pi/releases/latest*) echo "location: https://github.com/can1357/oh-my-pi/releases/tag/v%s"; exit 0 ;;\n' "$2"
		printf '*omp-termux/releases/latest*) echo "location: https://github.com/hmeqo/omp-termux/releases/tag/omp-%s"; exit 0 ;;\n' "$3"
		printf 'esac\nexec %s "$@"\n' "$REAL_CURL"
	} >"$1"
	chmod +x "$1"
}

echo "== device smoke (isolated HOME + TERMUX_VERSION, stubbed curl/bun)"
T=/tmp/vdev; FB=/tmp/vbin; RAW=/tmp/vraw; R19=/tmp/vrel19; R20=/tmp/vrel20; LOG=/tmp/v-bun.log; CURL_LOG=/tmp/v-curl.log
for d in "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG" "$CURL_LOG"; do
	case "$d" in /tmp/*) ;; *) echo "verify: refusing to touch $d" >&2; exit 1 ;; esac
done
rm -rf "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG" "$CURL_LOG"
mkdir -p "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/native" "$T/usr/bin" "$T/tmp" "$FB" "$RAW/bin" "$R19" "$R20" "$T/.config"
pkg_json "$V0" >"$T/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/package.json"
cp "$R/out/pi_natives.android-arm64.node" "$R/out/desktop-adapter.js" "$R19/"
cp "$R/out/desktop-adapter.js" "$R20/"
# $R19 serves the artifact as built. $R20 serves the same bytes with $V1 recorded the pre-stamp way (a
# __piNativesV<major>_<minor>_<patch> napi name, no stamp), so both identities the tool reads stay covered by
# the cases below — those are also what a release published before the stamp looks like.
LEGACY1="__piNativesV$(printf '%s' "$V1" | tr . _)"
python3 - <<PY
import pathlib
source = pathlib.Path("$R19/pi_natives.android-arm64.node").read_bytes()
if b"$ID" == b"__piNativesV" or source.count(b"$S0") != 1:
	pathlib.Path("$R20/pi_natives.android-arm64.node").write_bytes(source.replace(b"$S0", b"$S1"))
else:
	magic, legacy = b"$ID", b"$LEGACY1"
	assert source.count(magic) == 1
	at = source.index(magic)
	out = bytearray(source)
	out[at:at + len(magic) + len(legacy)] = bytes(len(magic)) + legacy
	assert out.count(legacy) == 1 and out.count(magic) == 0
	pathlib.Path("$R20/pi_natives.android-arm64.node").write_bytes(bytes(out))
PY
cp "$R/bin/omp-termux" "$RAW/bin/omp-termux"
fake_curl "$FB/curl" "$V1" "$V0"   # upstream is one ahead; this repository has published $V0, which $R19 serves
cat >"$FB/bun" <<EOS
#!/bin/sh
echo "bun \$* BUN_INSTALL=\${BUN_INSTALL:-unset}" >>"$LOG"
[ -f "$T/bunfail" ] && exit 1
if [ "\$1" = install ] && [ "\$2" = -g ]; then
	v="\${3#@oh-my-pi/pi-coding-agent@}"
	p="\${BUN_INSTALL:-$T/.bun}/install/cache/@oh-my-pi/pi-natives@\$v@@@1"
	mkdir -p "\$p/native"
	echo "{\\"name\\":\\"@oh-my-pi/pi-natives\\",\\"version\\":\\"\$v\\"}" >"\$p/package.json"
fi
exit 0
EOS
chmod +x "$FB"/*
HOME=$T TMPDIR=$T/tmp PREFIX=$T/usr XDG_CONFIG_HOME=$T/.config XDG_CACHE_HOME=$T/.cache TERMUX_VERSION=0.118 PATH="$FB:$PATH" \
	OMP_TERMUX_RAW_BASE="file://$RAW" OMP_TERMUX_RELEASE_BASE="file://$R19" sh "$R/install.sh" >/tmp/v1.log 2>&1
chk "bootstrap: install.sh exits 0" "$?" "0"
P="$T/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1"; TOOL="$T/usr/bin/omp-termux"
chk "bootstrap: addon in place" "$(ls "$P/native" | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
chk "bootstrap: tool persisted" "$([ -f "$T/.local/opt/omp-termux/bin/omp-termux" ] && echo yes)" "yes"
chk "symlink lands in \$PREFIX/bin" "$(readlink "$T/usr/bin/omp-termux")" "$T/.local/opt/omp-termux/bin/omp-termux"
chk "bootstrap: scratch removed" "$(ls -A "$T/tmp" | wc -l)" "0"
chk "bootstrap: omp untouched" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

# install.sh checks its prerequisites before fetching anything, so a PATH without bash must fail on that
# (and never get as far as curl).
PATH="$FB" "$REAL_SH" "$R/install.sh" >/tmp/v7.log 2>&1
chk "bootstrap: without bash exits !=0" "$(nonzero $?)" "non0"
grep -q 'install: bash is required' /tmp/v7.log && ok "bootstrap: says bash is required" || no "bootstrap: silent about bash"

CACHE="$T/.local/opt/omp-termux/cache/self-update"
dev() { # $1 = release base, $2 = verb, $3 = argument, $4 = OMP_TERMUX_NO_UPDATE_CHECK
	(
		HOME=$T; TMPDIR=$T/tmp; PREFIX=$T/usr; XDG_CONFIG_HOME=$T/.config; XDG_CACHE_HOME=$T/.cache
		TERMUX_VERSION=0.118; PATH="$FB:$PATH"; OMP_TERMUX_RAW_BASE="file://$RAW"; OMP_TERMUX_RELEASE_BASE="$1"
		export HOME TMPDIR PREFIX XDG_CONFIG_HOME XDG_CACHE_HOME TERMUX_VERSION PATH OMP_TERMUX_RAW_BASE OMP_TERMUX_RELEASE_BASE
		[ -n "${4:-}" ] && OMP_TERMUX_NO_UPDATE_CHECK="$4" && export OMP_TERMUX_NO_UPDATE_CHECK
		"$TOOL" "${2:-install}" "${3:-}"
	)
}

: >"$LOG"; rm -f "$CACHE"
dev "file://$R19" install >/tmp/v2.log 2>&1; chk "install (no argument) exits 0" "$?" "0"
chk "install (no argument) leaves omp alone" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"
grep -q 'nothing to do' /tmp/v2.log && ok "install (no argument): already at the published version" ||
	{ no "install (no argument) does not say nothing to do"; tail -3 /tmp/v2.log | sed 's|^|       |'; }
chk "install (no argument): nothing to do comes last" "$(tail -n1 /tmp/v2.log | grep -c 'nothing to do')" "1"
chk "install (no argument): does not re-link an existing link" "$(grep -c 'linked ' /tmp/v2.log)" "0"

fake_curl "$FB/curl" "$V1" "$V1"   # this repository publishes $V1 now, which $R20 serves
: >"$LOG"; rm -f "$CACHE"
dev "file://$R20" install latest >/tmp/v3.log 2>&1; chk "install latest exit=0" "$?" "0"
chk "calls bun to upgrade" "$(grep -o "install -g @oh-my-pi/pi-coding-agent@$V1" "$LOG" | head -1)" "install -g @oh-my-pi/pi-coding-agent@$V1"
chk "addon in place in the new package" "$(ls "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1/native" 2>/dev/null | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "

# Already at the published version: the release is never fetched, so nothing is downloaded.
: >"$LOG"; : >"$CURL_LOG"
dev "file:///tmp/vmissing" install latest >/tmp/v4.log 2>&1; chk "already up to date exits 0" "$?" "0"
grep -q 'nothing to do' /tmp/v4.log && ok "already up to date: says nothing to do" || no "already up to date: silent about nothing to do"
chk "already up to date: no download" "$(grep -c 'vmissing' "$CURL_LOG" 2>/dev/null || true)" "0"
chk "already up to date: bun not called" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

# An addon that is present but does not load must not reach the skip path: the release is fetched again.
: >"$LOG"; : >"$CURL_LOG"; : >"$T/bunfail"
dev "file://$R20" install latest >/tmp/vload.log 2>&1; loadrc=$?
rm -f "$T/bunfail"
chk "broken addon: the run fails on the load test" "$(nonzero "$loadrc")" "non0"
grep -q 'the installed addon does not load; reinstalling it' /tmp/vload.log &&
	ok "broken addon: says it is reinstalling" || { no "broken addon: silent about the reload"; tail -3 /tmp/vload.log | sed 's|^|       |'; }
chk "broken addon: nothing to do is not printed" "$(grep -c 'nothing to do' /tmp/vload.log)" "0"
chk "broken addon: the release is fetched again" "$(grep -c 'pi_natives.android-arm64.node' "$CURL_LOG")" "1"
chk "broken addon: omp untouched" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

# Upstream is ahead of what this repository publishes: that is news, not a failure.
fake_curl "$FB/curl" "$V2" "$V1"   # upstream two ahead of what is published here
: >"$LOG"
dev "file://$R20" install latest >/tmp/vup.log 2>&1; chk "upstream ahead exits 0" "$?" "0"
grep -q "upstream $V2 is published but has no build here yet" /tmp/vup.log &&
	ok "upstream ahead: says the build is missing here" || no "upstream ahead: silent about the missing build"
fake_curl "$FB/curl" "$V1" "$V1"

# Behind and the release it needs is gone: a real failure, and nothing on the device changes.
rm -rf "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1"
: >"$LOG"; dev "file:///tmp/vmissing" install latest >/tmp/v4.log 2>&1
chk "needed release missing exits !=0" "$(nonzero $?)" "non0"
chk "needed release missing: bun not called" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"
grep -q 'nothing was changed' /tmp/v4.log && ok "says nothing was changed" || no "silent about nothing was changed"

# A release whose addon reports another version is a wrong or truncated download, not an install.
: >"$LOG"; dev "file://$R19" install latest >/tmp/vwrong.log 2>&1
chk "wrong release exits !=0" "$(nonzero $?)" "non0"
grep -q "the downloaded addon is for $V0, not $V1" /tmp/vwrong.log && ok "names both versions" ||
	{ no "does not name both versions"; tail -2 /tmp/vwrong.log | sed 's|^|       |'; }
chk "wrong release: bun not called" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

# The device carries a version this repository never published (omp upgraded by hand): refuse, touch nothing.
mkdir -p "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native"
pkg_json "$V2" >"$T/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1/package.json"
cp "$R20/pi_natives.android-arm64.node" "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native/"
FA="$T/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native/pi_natives.android-arm64.node"
addon_before=$(sha256sum "$FA" | cut -d' ' -f1)
: >"$LOG"; dev "file://$R20" install latest >/tmp/vahead.log 2>&1
chk "device ahead exits !=0" "$(nonzero $?)" "non0"
grep -q "no build published here for the omp you run: $V2 (newest: omp-$V1)" /tmp/vahead.log &&
	ok "device ahead: names the versions" || { no "device ahead: does not name the versions"; tail -2 /tmp/vahead.log | sed 's|^|       |'; }
grep -q 'nothing was changed' /tmp/vahead.log && ok "device ahead: nothing was changed" || no "device ahead: silent about nothing changing"
chk "device ahead: bun not called" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"
chk "device ahead: addon untouched" "$(sha256sum "$FA" | cut -d' ' -f1)" "$addon_before"

# the no-argument form hits the same guard, with the addon gone: a device whose owner upgraded omp by hand
rm -f "$FA"
: >"$LOG"; dev "file://$R19" install >/tmp/vnoarg.log 2>&1
chk "no argument, device ahead exits !=0" "$(nonzero $?)" "non0"
grep -q "no build published here for the omp you run: $V2 (newest: omp-$V1)" /tmp/vnoarg.log &&
	ok "no argument, device ahead: names both versions" || { no "no argument, device ahead: does not name them"; tail -2 /tmp/vnoarg.log | sed 's|^|       |'; }
grep -q "you have          : omp-$V2 (addon missing)" /tmp/vnoarg.log &&
	ok "no argument, device ahead: panel says the addon is missing" || no "no argument: panel hides the missing addon"
chk "no argument, device ahead: bun not called" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

# The refusal covers the targets the tool picked; a version the caller names is theirs to step back to.
: >"$LOG"; dev "file://$R20" install "$V1" >/tmp/vstep.log 2>&1; chk "named version steps back" "$?" "0"
grep -q "no build published here" /tmp/vstep.log && no "named version: still refused" || ok "named version: not refused"
chk "named version: installs the version asked for" "$(grep -o "install -g @oh-my-pi/pi-coding-agent@$V1" "$LOG" | head -1)" "install -g @oh-my-pi/pi-coding-agent@$V1"
chk "named version: addon lands in that package" "$(ls "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1/native" 2>/dev/null | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
rm -rf "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1"   # later sections expect $V0/$V1 only

chk "update-self on identical content: already up to date" "$(dev "file://$R19" update-self 2>&1 | grep -c 'already up to date')" "1"
printf '\n# moved on\n' >>"$RAW/bin/omp-termux"
rm -f "$CACHE"
dev "file://$R19" status >/tmp/vcache.log 2>&1   # populates the cached view of the world
chk "status reports the published build" "$(grep -c "newest here: omp-$V1" /tmp/vcache.log)" "1"
chk "status reports the tool version" "$(grep -c 'version    : v[0-9.]* ([0-9a-f]\{12\})' /tmp/vcache.log)" "1"
chk "hint: one line when main differs" "$(dev "file://$R19" status 2>&1 >/dev/null | grep -c 'omp-termux update available:')" "1"
chk "hint: names both versions and hashes" \
	"$(dev "file://$R19" status 2>&1 >/dev/null | grep -c 'update available: v[0-9.]* ([0-9a-f]\{12\}) -> v[0-9.]* ([0-9a-f]\{12\}); run')" "1"
dev "file://$R19" update-self >/tmp/v5.log 2>&1; chk "update-self on changed content exits 0" "$?" "0"
grep -q 'updated [0-9a-f]\{12\} -> [0-9a-f]\{12\}' /tmp/v5.log && ok "prints both hashes" || no "does not print both hashes"
chk "update-self drops the cached view" "$([ -f "$CACHE" ] && echo present || echo gone)" "gone"
chk "hint: silent when main matches" "$(dev "file://$R19" status 2>&1 >/dev/null | grep -c 'update available')" "0"

: >"$CURL_LOG"
dev "file://$R19" status >/tmp/vttl.log 2>&1
chk "ttl: no request while the cache is fresh" "$(grep -c 'bin/omp-termux\|releases/latest' "$CURL_LOG" 2>/dev/null || true)" "0"
# A cache another copy wrote (the bootstrap, a manual copy, an older version of this test) describes a file
# that is not this one: trusting its remote hash would report an update that does not exist.
sed -i 's/^hash=.*/hash=0/; s/^self=.*/self=0/' "$CACHE"
: >"$CURL_LOG"
chk "cache from another copy: no invented hint" "$(dev "file://$R19" status 2>&1 >/dev/null | grep -c 'update available')" "0"
chk "cache from another copy: re-checks" "$(grep -c 'bin/omp-termux' "$CURL_LOG" 2>/dev/null || true)" "1"
chk "cache from another copy: records this copy" "$(grep -c "^self=$(sha256sum "$T/.local/opt/omp-termux/bin/omp-termux" | cut -d' ' -f1)$" "$CACHE")" "1"
rm -f "$CACHE"; : >"$CURL_LOG"
chk "opt-out: no hint" "$(dev "file://$R19" status "" 1 2>&1 >/dev/null | grep -c 'update available')" "0"
chk "opt-out: no request" "$(grep -c 'omp-termux' "$CURL_LOG" 2>/dev/null || true)" "0"
cp "$R/bin/omp-termux" "$RAW/bin/omp-termux"   # restore: later sections fetch the tool from here
printf 'if then fi((\n' >"$RAW/bin/omp-termux"
keep=$(sha256sum "$T/.local/opt/omp-termux/bin/omp-termux" | cut -c1-12)
dev "file://$R19" update-self >/tmp/v6.log 2>&1; chk "broken script exits !=0" "$(nonzero $?)" "non0"
cp "$R/bin/omp-termux" "$RAW/bin/omp-termux"
chk "broken script leaves the old copy intact" "$(sha256sum "$T/.local/opt/omp-termux/bin/omp-termux" | cut -c1-12)" "$keep"

echo
echo "== two bun roots: install into the one carrying omp (the tool's shell has neither XDG nor bun's bin)"
# The legacy root carries a newer addon but no omp: picking by rule order upgrades the root nobody runs.
mkdir -p "$T/.cache/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent" \
	"$T/.cache/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native"
pkg_json "$V0" >"$T/.cache/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent/package.json"
pkg_json "$V0" >"$T/.cache/.bun/install/global/node_modules/@oh-my-pi/pi-natives/package.json"
cp "$R/out/pi_natives.android-arm64.node" "$T/.cache/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native/"
: >"$LOG"
dev "file://$R20" install latest >/tmp/vroots.log 2>&1
chk "two roots: upgrade exits 0" "$?" "0"
grep -q "installing omp $V1 on this device" /tmp/vroots.log && ok "two roots: picked the root carrying omp" || no "two roots: picked the wrong root"
chk "two roots: root pinned (BUN_INSTALL)" "$(grep -o "BUN_INSTALL=$T/.cache/.bun\$" "$LOG" | head -1)" "BUN_INSTALL=$T/.cache/.bun"
chk "two roots: new package lands in that root" "$(ls "$T/.cache/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1/native" 2>/dev/null | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "

echo
echo "== only another version on the device: install fails and names what it scanned"
TM=/tmp/vmismatch
case "$TM" in /tmp/*) ;; *) echo "verify: refusing to touch $TM" >&2; exit 1 ;; esac
rm -rf "$TM"; mkdir -p "$TM/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1/native" "$TM/usr/bin" "$TM/tmp" "$TM/.config"
pkg_json "$V1" >"$TM/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1/package.json"
HOME=$TM TMPDIR=$TM/tmp PREFIX=$TM/usr XDG_CONFIG_HOME=$TM/.config XDG_CACHE_HOME=$TM/.cache TERMUX_VERSION=0.118 PATH="$FB:$PATH" \
	bash "$R/bin/omp-termux" install "$R/out/pi_natives.android-arm64.node" >/tmp/vmismatch.log 2>&1
chk "other version only: exits !=0" "$(nonzero $?)" "non0"
grep -q "found: $V1" /tmp/vmismatch.log && ok "the error names the version it scanned" || { no "the error does not name the version"; tail -2 /tmp/vmismatch.log | sed 's|^|       |'; }
chk "no .new left behind" "$(ls "$T/.local/opt/omp-termux/bin" | tr '\n' ' ')" "omp-termux "
chk "no stray files on the device" "$(find "$T" -type f -not -path '*/.config/*' -not -path '*/.bun/*' -not -path '*/.cache/*' -not -path '*/.local/*' 2>/dev/null | tr '\n' ' ')" ""

echo "== a plain machine: the tool runs, and the build half only builds"
TW=/tmp/vws; FSW=/tmp/vwsbin
case "$TW$FSW" in /tmp/*) ;; *) echo "verify: refusing to touch $TW$FSW" >&2; exit 1 ;; esac
rm -rf "$TW" "$FSW"
mkdir -p "$TW/.config" "$FSW"
printf '#!/bin/sh\nexit 0\n' >"$FSW/bun"
chmod +x "$FSW"/*
ws() { HOME=$TW XDG_CONFIG_HOME=$TW/.config XDG_CACHE_HOME=$TW/.cache PATH="$FSW:$PATH" bash "$R/bin/omp-termux" "$@" >/tmp/vws.log 2>&1; }
ws help; chk "workstation help exits 0" "$?" "0"
# The tool has no mode: it reports the pi-natives of whatever machine runs it, and there are none here.
ws status; chk "status exits 0 with nothing installed" "$?" "0"
grep -q "tool       : $R/bin/omp-termux" /tmp/vws.log && ok "status reports this copy" || no "status does not name the running copy"
ws doctor; chk "doctor exits 0 anywhere" "$?" "0"
grep -q 'Termux         : not detected' /tmp/vws.log && ok "doctor reports what it sees" || no "doctor reports nothing"
ws verify; chk "verify with no pi-natives exits !=0" "$(nonzero $?)" "non0"
grep -q 'no @oh-my-pi/pi-natives on this machine' /tmp/vws.log && ok "verify says what is missing" ||
	{ no "verify does not name what is missing"; tail -1 /tmp/vws.log | sed 's|^|       |'; }
ws build 18.3.4; chk "build is not a tool verb" "$(nonzero $?)" "non0"
grep -q 'unknown verb: build' /tmp/vws.log && ok "build: the tool says so" || no "build: the tool is quiet"
# The tool puts its own copy in place while installing an addon; that copy is what uninstall-self removes.
mkdir -p "$TW/.local/opt/omp-termux/bin" "$TW/.local/bin"
cp "$R/bin/omp-termux" "$TW/.local/opt/omp-termux/bin/omp-termux"
ln -s "$TW/.local/opt/omp-termux/bin/omp-termux" "$TW/.local/bin/omp-termux"
ws uninstall-self; chk "uninstall-self exits 0 anywhere" "$?" "0"
chk "uninstall-self removes the copy and the link" \
	"$({ [ -e "$TW/.local/opt/omp-termux" ] || [ -e "$TW/.local/bin/omp-termux" ]; } && echo exists || echo gone)" "gone"

echo "== the build half: its own list of verbs, and it names itself"
wsd() { HOME=$TW XDG_CONFIG_HOME=$TW/.config XDG_CACHE_HOME=$TW/.cache PATH="$FSW:$PATH" bash "$R/dev/omp-termux-dev" "$@" >/tmp/vwsd.log 2>&1; }
wsd help; chk "build half help exits 0" "$?" "0"
grep -q 'omp-termux-dev build \[version\]' /tmp/vwsd.log && ok "build half lists its verbs" || no "build half lists no verbs"
wsd bogus; chk "build half rejects an unknown verb" "$(nonzero $?)" "non0"
wsd build --oops; chk "build half rejects an option-looking argument" "$(nonzero $?)" "non0"
grep -q "run 'omp-termux-dev help'" /tmp/vwsd.log && ok "build half names itself in the hint" || no "build half names the tool"
echo "== workstation → device: the build half drives the target over ssh (stubbed ssh/scp, fake device)"
TS=/tmp/vssh; FS=/tmp/vsshbin
case "$TS$FS" in /tmp/*) ;; *) echo "verify: refusing to touch $TS$FS" >&2; exit 1 ;; esac
rm -rf "$TS" "$FS"
mkdir -p "$TS/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native" "$TS/usr/bin" "$TS/tmp" "$TS/.config" "$FS"
pkg_json "$V0" >"$TS/.bun/install/global/node_modules/@oh-my-pi/pi-natives/package.json"
# ssh runs the command line it is handed against the fake device's HOME; scp copies into it. Both log.
cat >"$FS/ssh" <<'STUB'
#!/bin/sh
printf 'ssh %s\n' "$*" >>/tmp/vssh.log
while [ $# -gt 0 ]; do case "$1" in -p) shift 2 ;; -o) shift 2 ;; *) break ;; esac; done
shift                                       # the host
exec env HOME=/tmp/vssh TMPDIR=/tmp/vssh/tmp PREFIX=/tmp/vssh/usr XDG_CONFIG_HOME=/tmp/vssh/.config \
	XDG_CACHE_HOME=/tmp/vssh/.cache TERMUX_VERSION=0.118 PATH="/tmp/vsshbin:$PATH" sh -c "$*"
STUB
cat >"$FS/scp" <<'STUB'
#!/bin/sh
printf 'scp %s\n' "$*" >>/tmp/vssh.log
src=""; dst=""
while [ $# -gt 0 ]; do
	case "$1" in
		-P) shift 2 ;;
		-*) shift ;;
		*:*) dst="$1"; shift ;;
		*) [ -z "$src" ] && src="$1"; shift ;;
	esac
done
rel="$(printf '%s' "$dst" | sed 's/^[^:]*://; s|^~/*||')"
mkdir -p "/tmp/vssh/$rel"
exec cp -f "$src" "/tmp/vssh/$rel/"
STUB
printf '#!/bin/sh\nexit 0\n' >"$FS/bun"
chmod +x "$FS"/*
: >/tmp/vssh.log
HOME="$TW" XDG_CONFIG_HOME="$TW/.config" OMP_TERMUX_HOST=user@device OMP_TERMUX_PORT=8022 \
	PATH="$FS:$PATH" bash "$R/dev/omp-termux-dev" install "$R/out/pi_natives.android-arm64.node" >/tmp/vssh-install.log 2>&1
chk "device install exits 0" "$?" "0"
chk "device install: no rebuild for a local artifact" "$(grep -c 'cross-compiling' /tmp/vssh-install.log)" "0"
chk "device install: uploads the tool (install + verify), the artifact and its adapter" \
	"$(grep -c '^scp -P 8022' /tmp/vssh.log)" "4"
grep -q "^scp .*out/pi_natives\.android-arm64\.node user@device:" /tmp/vssh.log &&
	ok "device install: the artifact goes to the device scratch" || no "device install: artifact not uploaded"
grep -q "^scp .*out/desktop-adapter\.js user@device:" /tmp/vssh.log &&
	ok "device install: the adapter goes with it" || no "device install: adapter not uploaded"
chk "device install: the device ends up with the addon" \
	"$(ls "$TS/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native" | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
chk "device install: the device keeps the tool" "$([ -f "$TS/.local/opt/omp-termux/bin/omp-termux" ] && echo yes)" "yes"
chk "device install: leaves no scratch behind" "$([ -d "$TS/.cache/omp-termux" ] && echo present || echo gone)" "gone"
chk "device install: verifies on the device" "$(grep -c 'all good' /tmp/vssh-install.log)" "1"
HOME="$TW" XDG_CONFIG_HOME="$TW/.config" OMP_TERMUX_HOST=user@device OMP_TERMUX_PORT=8022 \
	PATH="$FS:$PATH" bash "$R/dev/omp-termux-dev" status >/tmp/vssh-status.log 2>&1
chk "device status exits 0" "$?" "0"
grep -q "tool       : /tmp/vssh/.cache/omp-termux/omp-termux" /tmp/vssh-status.log &&
	ok "device status: ran the uploaded copy on the device" || no "device status: did not reach the device"
grep -q 'omp-termux\\ status' /tmp/vssh.log && ok "device status: ran the uploaded tool there" || no "device status: never asked the device"

echo "== XDG roots (BUN_INSTALL / XDG_CACHE_HOME / ~/.bun)"
TX=/tmp/verify-xdg; FX=/tmp/verify-xbin; RX=/tmp/verify-xrel
rm -rf "$TX" "$FX" "$RX"
case "$TX$FX$RX" in /tmp/*) ;; *) echo "verify: refusing to touch $TX" >&2; exit 1 ;; esac
mkdir -p "$TX" "$FX" "$RX"
XDGR="$TX/.cache/.bun"; LEGR="$TX/.bun"
XPKG="$XDGR/install/cache/@oh-my-pi/pi-natives@$V2@@@1"
mkdir -p "$XPKG/native" "$XDGR/install/global/node_modules/@oh-my-pi/pi-natives/native" \
	"$LEGR/install/cache/@oh-my-pi/pi-natives@$V0@@@1/native" "$TX/usr/bin" "$TX/tmp" "$TX/.config"
pkg_json "$V2" >"$XPKG/package.json"
pkg_json "$V2" >"$XDGR/install/global/node_modules/@oh-my-pi/pi-natives/package.json"
pkg_json "$V0" >"$LEGR/install/cache/@oh-my-pi/pi-natives@$V0@@@1/package.json"
cp "$R/out/pi_natives.android-arm64.node" "$LEGR/install/cache/@oh-my-pi/pi-natives@$V0@@@1/native/"
cp "$R/out/desktop-adapter.js" "$RX/"
python3 -c "
import pathlib
b = pathlib.Path('$R/out/pi_natives.android-arm64.node').read_bytes()
pathlib.Path('$RX/pi_natives.android-arm64.node').write_bytes(b.replace(b'$S0', b'$S2'))"
fake_curl "$FX/curl" "$V1" "$V2"   # this repository publishes the $V2 the fixture carries
printf '#!/bin/sh\nexit 0\n' >"$FX/bun"
chmod +x "$FX/curl" "$FX/bun"
HOME=$TX XDG_CACHE_HOME="$TX/.cache" TMPDIR=$TX/tmp PREFIX=$TX/usr XDG_CONFIG_HOME=$TX/.config TERMUX_VERSION=0.118 \
	PATH="$FX:$PATH" OMP_TERMUX_RELEASE_BASE="file://$RX" bash "$R/bin/omp-termux" install >/tmp/verify-xdg.log 2>&1
chk "XDG root: install uses the version it should" "$(grep -c "fetching pi-natives $V2" /tmp/verify-xdg.log)" "1"
[ -f "$XPKG/native/pi_natives.android-arm64.node" ] && ok "XDG root: addon lands in the package in use" || no "XDG root: addon missing from the package in use"
[ -d "$LEGR/install/cache/@oh-my-pi/pi-natives@$V0@@@1" ] && no "XDG root: old-root copy not reclaimed" || ok "XDG root: old-root copy reclaimed by the rules"

echo "== BUN_INSTALL wins over both default roots"
BI="$TX/bi"
mkdir -p "$BI/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native" "$TX/usr/bin"
pkg_json "$V2" >"$BI/install/cache/@oh-my-pi/pi-natives@$V2@@@1/package.json"
HOME=$TX BUN_INSTALL="$BI" XDG_CACHE_HOME="$TX/.cache" TMPDIR=$TX/tmp PREFIX=$TX/usr XDG_CONFIG_HOME=$TX/.config \
	TERMUX_VERSION=0.118 PATH="$FX:$PATH" OMP_TERMUX_RELEASE_BASE="file://$RX" bash "$R/bin/omp-termux" install \
	>/tmp/verify-bi.log 2>&1
[ -f "$BI/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native/pi_natives.android-arm64.node" ] &&
	ok "BUN_INSTALL root got the addon" || no "BUN_INSTALL root got no addon"

echo "== fresh device: curl bootstrap (no bun, no omp)"
TF=/tmp/verify-fresh; FF=/tmp/verify-fbin; RF=/tmp/verify-frel; FW=/tmp/verify-fraw
rm -rf "$TF" "$FF" "$RF" "$FW"
case "$TF$FF$RF$FW" in /tmp/*) ;; *) echo "verify: refusing to touch $TF" >&2; exit 1 ;; esac
mkdir -p "$TF" "$FF" "$RF" "$FW/bin" "$TF/usr/bin" "$TF/tmp" "$TF/.config"
cp "$R/bin/omp-termux" "$FW/bin/omp-termux"
python3 -c "
import pathlib
b = pathlib.Path('$R/out/pi_natives.android-arm64.node').read_bytes()
pathlib.Path('$RF/pi_natives.android-arm64.node').write_bytes(b.replace(b'$S0', b'$S2'))"
cp "$R/out/desktop-adapter.js" "$RF/"
fake_curl "$FF/curl" "$V2" "$V2"
cat >"$FF/pkg" <<'PEOF'
#!/bin/sh
# stand-in for Termux' pkg: drops a fake bun where bun would live
printf '%s\n' "pkg $* PKGROOT=${PKGROOT:-UNSET}" >>"$PKGLOG"
case "$1" in
install)
	mkdir -p "$PKGROOT/bin"
	cat >"$PKGROOT/bin/bun" <<'BUNF'
#!/bin/sh
echo "bun $*" >>"$BUNLOG"
if [ "$1" = install ] && [ "$2" = -g ]; then
	v="${3#@oh-my-pi/pi-coding-agent@}"
	p="$PKGROOT/install/cache/@oh-my-pi/pi-natives@$v@@@1"
	mkdir -p "$p/native"
	echo "{\"name\":\"@oh-my-pi/pi-natives\",\"version\":\"$v\"}" >"$p/package.json"
fi
exit 0
BUNF
	chmod +x "$PKGROOT/bin/bun"
	exit 0 ;;
esac
exit 0
PEOF
chmod +x "$FF/curl" "$FF/pkg"
: >"$TF/bun.log"; : >"$TF/pkg.log"
# A system-wide bun would make the tool think bun is already there, so hide it behind a bind mount of /dev/null
# inside a private mount namespace. Without that privilege the case is skipped.
FRC=127
if unshare -rm true 2>/dev/null; then
	HOME=$TF XDG_CACHE_HOME= TMPDIR=$TF/tmp PREFIX=$TF/usr XDG_CONFIG_HOME=$TF/.config TERMUX_VERSION=0.118 \
		PATH="$FF:$PATH" PKGROOT="$TF/.bun" BUNLOG="$TF/bun.log" PKGLOG="$TF/pkg.log" OMP_TERMUX_RAW_BASE="file://$FW" \
		OMP_TERMUX_RELEASE_BASE="file://$RF" \
		unshare -rm sh -c 'mount --bind /dev/null "$1" 2>/dev/null; exec sh "$2"' _ "${REAL_BUN:-/dev/null}" "$R/install.sh" \
		>/tmp/verify-fresh.log 2>&1
	FRC=$?
else
	echo "  (skip: unshare -rm unavailable, cannot hide a system-wide bun)"
fi
if [ "$FRC" = 127 ]; then
	:
elif [ "$FRC" -eq 0 ]; then
	ok "fresh device: bootstrap exits 0"
else
	no "fresh device: bootstrap failed"
	tail -4 /tmp/verify-fresh.log | sed 's|^|       |'
fi
if [ "$FRC" != 127 ]; then
grep -q "installing bun" /tmp/verify-fresh.log && ok "fresh device: installed bun itself" || no "fresh device: no bun"
grep -q "no omp on this device yet" /tmp/verify-fresh.log && ok "fresh device: installed omp itself (this repository's newest release)" || no "fresh device: no omp"
grep -q "install -g @oh-my-pi/pi-coding-agent@$V2" "$TF/bun.log" && ok "fresh device: calls the right version" || no "fresh device: wrong bun call"
[ -f "$TF/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native/pi_natives.android-arm64.node" ] &&
	ok "fresh device: addon lands in the new omp" || no "fresh device: addon missing"
[ -f "$TF/.local/opt/omp-termux/bin/omp-termux" ] && ok "fresh device: tool stays on the device" || no "fresh device: tool not left behind"
fi

if [ "$fail" = 0 ]; then
	rm -rf "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG" "$TW" "$FSW" "$TX" "$FX" "$RX" "$TF" "$FF" "$RF" "$FW" "$TM" /tmp/verify-xdg.log /tmp/verify-bi.log /tmp/verify-fresh.log /tmp/vmismatch.log
else
	echo "  (failed: scene kept under /tmp/verify-*)"
fi
echo
echo "failures: $fail"
exit $fail
