#!/bin/sh
# Local verification: static gates, then both modes against a fake device.
#
#   sh tests/verify.sh
#
# The device-side and workstation-side sections need out/pi_natives.android-arm64.node (run
# `./bin/omp-termux build <version>` first); without it they are skipped. Nothing here touches a real device or
# the network: ssh/scp/bun/curl are stubbed, HOME/TMPDIR/XDG_CONFIG_HOME are isolated, and device mode is forced
# with TERMUX_VERSION. Every path that may be removed is a hard-coded /tmp path and asserted below.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
[ -n "$R" ] && [ -f "$R/bin/omp-termux" ] || { echo "verify: cannot locate the repository; refusing to run" >&2; exit 1; }
fail=0
ok() { printf '  ok   %s\n' "$1"; }
no() { printf '  FAIL %s\n' "$1"; fail=1; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got [$2] want [$3])"; fi; }
nonzero() { [ "$1" -ne 0 ] && echo non0 || echo zero; }

echo "== 静态门禁"
bash -n "$R/bin/omp-termux" && ok "bash -n bin/omp-termux" || no "bash -n bin/omp-termux"
sh -n "$R/install.sh" && ok "sh -n install.sh" || no "sh -n install.sh"
python3 -c "import yaml,pathlib;yaml.safe_load(pathlib.Path('$R/.github/workflows/build.yml').read_text())" 2>/dev/null &&
	ok "CI YAML 可解析" || no "CI YAML 不可解析"
bash "$R/bin/omp-termux" bogus >/dev/null 2>&1; chk "未知动词 exit=1" "$?" "1"
bash "$R/bin/omp-termux" install --help >/dev/null 2>&1; chk "install --help 被拒" "$?" "1"
bash "$R/bin/omp-termux" build --help >/dev/null 2>&1; chk "build --help 被拒" "$?" "1"

if [ ! -f "$R/out/pi_natives.android-arm64.node" ]; then
	echo "== 跳过设备侧与工作站侧(缺 out/pi_natives.android-arm64.node;先跑 ./bin/omp-termux build <version>)"
	echo
	echo "失败项: $fail"
	exit $fail
fi

REAL_CURL="$(command -v curl || true)"
REAL_SH="$(command -v sh || true)"
[ -n "$REAL_SH" ] || { echo "verify: sh is required" >&2; exit 1; }
[ -n "$REAL_CURL" ] || { echo "verify: curl is required" >&2; exit 1; }
REAL_BUN="$(command -v bun || true)"

# The fixtures follow the artifact in out/: the addon's sentinel must equal the package version it is
# installed into, and the "newer" fixtures must sort above it. The bumped versions keep the digit count
# of the sentinel so it can be rewritten in place.
V0="$(grep -ao '__piNativesV[0-9A-Za-z_]*' "$R/out/pi_natives.android-arm64.node" | head -1 | sed 's/^__piNativesV//; s/_/./g')"
[ -n "$V0" ] || { echo "verify: no version sentinel in out/pi_natives.android-arm64.node" >&2; exit 1; }
bump_version() { # $1 = version, $2 = how many releases ahead of it
	local major minor patch n
	major="${1%%.*}"; minor="${1#*.}"; minor="${minor%%.*}"; patch="${1##*.}"
	n=$((patch + $2))
	while [ "$n" -gt 9 ]; do minor=$((minor + 1)); n=$((n - 10)); done
	printf '%s.%s.%s' "$major" "$minor" "$n"
}
V1="$(bump_version "$V0" 1)"; V2="$(bump_version "$V0" 2)"
S0="__piNativesV$(printf '%s' "$V0" | tr . _)"
S1="__piNativesV$(printf '%s' "$V1" | tr . _)"
S2="__piNativesV$(printf '%s' "$V2" | tr . _)"

pkg_json() { printf '{"name":"@oh-my-pi/pi-natives","version":"%s"}' "$1"; }

# $1 = where to write it, $2 = the newest upstream release it answers, $3 = this repository's release
fake_curl() {
	{
		printf '#!/bin/sh\ncase "$*" in\n'
		printf '*api.github.com/repos/*/omp-termux/releases/latest*) echo '"'"'{"tag_name": "omp-%s"}'"'"'; exit 0 ;;\n' "$3"
		printf '*api.github.com*oh-my-pi*) echo '"'"'{"tag_name": "v%s"}'"'"'; exit 0 ;;\n' "$2"
		printf 'esac\nexec %s "$@"\n' "$REAL_CURL"
	} >"$1"
	chmod +x "$1"
}

echo "== 设备侧冒烟(隔离 HOME + TERMUX_VERSION,假 curl/bun)"
T=/tmp/vdev; FB=/tmp/vbin; RAW=/tmp/vraw; R19=/tmp/vrel19; R20=/tmp/vrel20; LOG=/tmp/v-bun.log
for d in "$T" "$FB" "$RAW" "$R19" "$R20"; do
	case "$d" in /tmp/*) ;; *) echo "verify: refusing to touch $d" >&2; exit 1 ;; esac
done
rm -rf "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG"
mkdir -p "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/native" "$T/usr/bin" "$T/tmp" "$FB" "$RAW/bin" "$R19" "$R20" "$T/.config"
pkg_json "$V0" >"$T/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/package.json"
cp "$R/out/pi_natives.android-arm64.node" "$R/out/desktop-adapter.js" "$R19/"
cp "$R/out/desktop-adapter.js" "$R20/"
python3 - <<PY
import pathlib
b = pathlib.Path("$R19/pi_natives.android-arm64.node").read_bytes()
assert b.count(b"$S0") == 1
pathlib.Path("$R20/pi_natives.android-arm64.node").write_bytes(b.replace(b"$S0", b"$S1"))
PY
cp "$R/bin/omp-termux" "$RAW/bin/omp-termux"
fake_curl "$FB/curl" "$V1" "$V1"
cat >"$FB/bun" <<EOS
#!/bin/sh
echo "bun \$*" >>"$LOG"
if [ "\$1" = install ] && [ "\$2" = -g ]; then
	v="\${3#@oh-my-pi/pi-coding-agent@}"
	p="$T/.bun/install/cache/@oh-my-pi/pi-natives@\$v@@@1"
	mkdir -p "\$p/native"
	echo "{\\"name\\":\\"@oh-my-pi/pi-natives\\",\\"version\\":\\"\$v\\"}" >"\$p/package.json"
fi
exit 0
EOS
chmod +x "$FB"/*
HOME=$T TMPDIR=$T/tmp PREFIX=$T/usr XDG_CONFIG_HOME=$T/.config TERMUX_VERSION=0.118 PATH="$FB:$PATH" \
	OMP_TERMUX_RAW_BASE="file://$RAW" OMP_TERMUX_RELEASE_BASE="file://$R19" sh "$R/install.sh" >/tmp/v1.log 2>&1
chk "引导 install.sh exit=0" "$?" "0"
P="$T/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1"; TOOL="$T/usr/bin/omp-termux"
chk "引导后插件就位" "$(ls "$P/native" | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
chk "引导后工具持久化" "$([ -f "$T/.local/opt/omp-termux/bin/omp-termux" ] && echo yes)" "yes"
chk "软链落在 \$PREFIX/bin" "$(readlink "$T/usr/bin/omp-termux")" "$T/.local/opt/omp-termux/bin/omp-termux"
chk "引导临时目录已清" "$(ls -A "$T/tmp" | wc -l)" "0"
chk "引导未动 omp" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

# install.sh checks its prerequisites before fetching anything, so a PATH without bash must fail on that
# (and never get as far as curl).
PATH="$FB" "$REAL_SH" "$R/install.sh" >/tmp/v7.log 2>&1
chk "引导:缺 bash 时 exit!=0" "$(nonzero $?)" "non0"
grep -q 'install: bash is required' /tmp/v7.log && ok "引导:提示缺 bash" || no "引导:未提示缺 bash"

dev() { HOME=$T TMPDIR=$T/tmp PREFIX=$T/usr XDG_CONFIG_HOME=$T/.config TERMUX_VERSION=0.118 PATH="$FB:$PATH" \
	OMP_TERMUX_RAW_BASE="file://$RAW" OMP_TERMUX_RELEASE_BASE="$1" "$TOOL" ${2:-install} "${3:-}"; }

: >"$LOG"; dev "file://$R19" install >/tmp/v2.log 2>&1; chk "install(无参) exit=0" "$?" "0"
chk "install(无参)未升级 omp" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"
: >"$LOG"; dev "file://$R20" install latest >/tmp/v3.log 2>&1; chk "install latest exit=0" "$?" "0"
chk "调用了 bun 升级" "$(grep -o "install -g @oh-my-pi/pi-coding-agent@$V1" "$LOG" | head -1)" "install -g @oh-my-pi/pi-coding-agent@$V1"
chk "新版包内插件就位" "$(ls "$T/.bun/install/cache/@oh-my-pi/pi-natives@$V1@@@1/native" 2>/dev/null | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
: >"$LOG"; dev "file:///tmp/vmissing" install latest >/tmp/v4.log 2>&1
chk "release 缺失时 exit!=0" "$(nonzero $?)" "non0"
chk "release 缺失时 bun 零调用" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"
grep -q 'nothing was changed' /tmp/v4.log && ok "提示 nothing was changed" || no "缺少 nothing was changed 提示"

chk "update-self 内容相同 → 已最新" "$(dev "file://$R19" update-self 2>&1 | grep -c 'already up to date')" "1"
printf '\n# moved on\n' >>"$RAW/bin/omp-termux"
dev "file://$R19" update-self >/tmp/v5.log 2>&1; chk "update-self 变更 exit=0" "$?" "0"
grep -q 'updated [0-9a-f]\{12\} -> [0-9a-f]\{12\}' /tmp/v5.log && ok "打印新旧哈希" || no "未打印新旧哈希"
printf 'if then fi((\n' >"$RAW/bin/omp-termux"
keep=$(sha256sum "$T/.local/opt/omp-termux/bin/omp-termux" | cut -c1-12)
dev "file://$R19" update-self >/tmp/v6.log 2>&1; chk "坏脚本 exit!=0" "$(nonzero $?)" "non0"
cp "$R/bin/omp-termux" "$RAW/bin/omp-termux"   # restore: later sections fetch the tool from here
chk "坏脚本时旧副本完好" "$(sha256sum "$T/.local/opt/omp-termux/bin/omp-termux" | cut -c1-12)" "$keep"
chk "无 .new 残留" "$(ls "$T/.local/opt/omp-termux/bin" | tr '\n' ' ')" "omp-termux "
chk "设备无计划外文件" "$(find "$T" -type f -not -path '*/.config/*' -not -path '*/.bun/*' -not -path '*/.local/*' 2>/dev/null | tr '\n' ' ')" ""

echo "== 工作站侧冒烟(假 ssh/scp 当设备)"
TW=/tmp/vws; FSW=/tmp/vwsbin
case "$TW$FSW" in /tmp/*) ;; *) echo "verify: refusing to touch $TW$FSW" >&2; exit 1 ;; esac
rm -rf "$TW" "$FSW"
mkdir -p "$TW/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/native" "$TW/.config" "$FSW"
pkg_json "$V0" >"$TW/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/package.json"
printf '#!/bin/sh\nfor a in "$@"; do cmd="$a"; done\nHOME="%s" PATH="%s:$PATH" sh -c "$cmd"\n' "$TW" "$FSW" >"$FSW/ssh"
printf '#!/bin/sh\nfor a in "$@"; do [ -f "$a" ] && { mkdir -p "%s/.cache/omp-termux"; cp -f "$a" "%s/.cache/omp-termux/"; }; done\nexit 0\n' "$TW" "$TW" >"$FSW/scp"
printf '#!/bin/sh\nexit 0\n' >"$FSW/bun"
chmod +x "$FSW"/*
ws() { HOME=$TW XDG_CONFIG_HOME=$TW/.config OMP_TERMUX_HOST=user@device PATH="$FSW:$PATH" bash "$R/bin/omp-termux" "$@" >/tmp/vws.log 2>&1; }
for v in help doctor status verify; do ws "$v" && ok "工作站 $v exit=0" || no "工作站 $v 失败"; done
ws install $V0 && ok "工作站 install $V0 exit=0" || { no "工作站 install 失败"; tail -3 /tmp/vws.log | sed 's|^|       |'; }
chk "工作站安装后设备侧插件就位" "$(ls "$TW/.bun/install/cache/@oh-my-pi/pi-natives@$V0@@@1/native" | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
ws install-self && ok "工作站 install-self exit=0" || no "install-self 失败"
chk "install-self 建链" "$(readlink "$TW/.local/bin/omp-termux" 2>/dev/null)" "$TW/.local/opt/omp-termux/bin/omp-termux"
ws uninstall-self && ok "工作站 uninstall-self exit=0" || no "uninstall-self 失败"
chk "uninstall-self 清干净" "$([ -e "$TW/.local/opt/omp-termux" ] && echo exists || echo gone)" "gone"
echo "== XDG 根(BUN_INSTALL / XDG_CACHE_HOME / ~/.bun)"
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
cp "$FB/curl" "$FX/curl" 2>/dev/null || fake_curl "$FX/curl" "$V1" "$V1"
printf '#!/bin/sh\nexit 0\n' >"$FX/bun"
chmod +x "$FX/curl" "$FX/bun"
HOME=$TX XDG_CACHE_HOME="$TX/.cache" TMPDIR=$TX/tmp PREFIX=$TX/usr XDG_CONFIG_HOME=$TX/.config TERMUX_VERSION=0.118 \
	PATH="$FX:$PATH" OMP_TERMUX_RELEASE_BASE="file://$RX" bash "$R/bin/omp-termux" install >/tmp/verify-xdg.log 2>&1
chk "XDG 根:install 用在该在的版本上" "$(grep -c "fetching pi-natives $V2" /tmp/verify-xdg.log)" "1"
[ -f "$XPKG/native/pi_natives.android-arm64.node" ] && ok "XDG 根:插件装进在用包目录" || no "XDG 根:插件没装进在用包目录"
[ -d "$LEGR/install/cache/@oh-my-pi/pi-natives@$V0@@@1" ] && no "XDG 根:旧根旧拷贝未回收" || ok "XDG 根:旧根旧拷贝按规则回收"

echo "== BUN_INSTALL 优先于两个默认根"
BI="$TX/bi"
mkdir -p "$BI/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native" "$TX/usr/bin"
pkg_json "$V2" >"$BI/install/cache/@oh-my-pi/pi-natives@$V2@@@1/package.json"
HOME=$TX BUN_INSTALL="$BI" XDG_CACHE_HOME="$TX/.cache" TMPDIR=$TX/tmp PREFIX=$TX/usr XDG_CONFIG_HOME=$TX/.config \
	TERMUX_VERSION=0.118 PATH="$FX:$PATH" OMP_TERMUX_RELEASE_BASE="file://$RX" bash "$R/bin/omp-termux" install \
	>/tmp/verify-bi.log 2>&1
[ -f "$BI/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native/pi_natives.android-arm64.node" ] &&
	ok "BUN_INSTALL 根里的包装上了插件" || no "BUN_INSTALL 根没装上插件"

echo "== 全新设备:curl 引导(缺 bun、缺 omp)"
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
	ok "全新设备:引导 exit=0"
else
	no "全新设备:引导失败"
	tail -4 /tmp/verify-fresh.log | sed 's|^|       |'
fi
if [ "$FRC" != 127 ]; then
grep -q "installing bun" /tmp/verify-fresh.log && ok "全新设备:自行装了 bun" || no "全新设备:没装 bun"
grep -q "no omp on this device yet" /tmp/verify-fresh.log && ok "全新设备:自行装了 omp(我们最新 release 的版本)" || no "全新设备:没装 omp"
grep -q "install -g @oh-my-pi/pi-coding-agent@$V2" "$TF/bun.log" && ok "全新设备:调用的是正确版本" || no "全新设备:bun 调用不对"
[ -f "$TF/.bun/install/cache/@oh-my-pi/pi-natives@$V2@@@1/native/pi_natives.android-arm64.node" ] &&
	ok "全新设备:插件装进新装的 omp 里" || no "全新设备:插件没装上"
[ -f "$TF/.local/opt/omp-termux/bin/omp-termux" ] && ok "全新设备:工具留在设备上" || no "全新设备:工具没留下"
fi

if [ "$fail" = 0 ]; then
	rm -rf "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG" "$TW" "$FSW" "$TX" "$FX" "$RX" "$TF" "$FF" "$RF" "$FW" /tmp/verify-xdg.log /tmp/verify-bi.log /tmp/verify-fresh.log
else
	echo "  (failed: scene kept under /tmp/verify-*)"
fi
echo
echo "失败项: $fail"
exit $fail
