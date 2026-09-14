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

echo "== 设备侧冒烟(隔离 HOME + TERMUX_VERSION,假 curl/bun)"
T=/tmp/vdev; FB=/tmp/vbin; RAW=/tmp/vraw; R19=/tmp/vrel19; R20=/tmp/vrel20; LOG=/tmp/v-bun.log
for d in "$T" "$FB" "$RAW" "$R19" "$R20"; do
	case "$d" in /tmp/*) ;; *) echo "verify: refusing to touch $d" >&2; exit 1 ;; esac
done
rm -rf "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG"
mkdir -p "$T/.bun/install/cache/@oh-my-pi/pi-natives@18.1.19@@@1/native" "$T/usr/bin" "$T/tmp" "$FB" "$RAW/bin" "$R19" "$R20" "$T/.config"
echo '{"name":"@oh-my-pi/pi-natives","version":"18.1.19"}' >"$T/.bun/install/cache/@oh-my-pi/pi-natives@18.1.19@@@1/package.json"
cp "$R/out/pi_natives.android-arm64.node" "$R/out/desktop-adapter.js" "$R19/"
cp "$R/out/desktop-adapter.js" "$R20/"
python3 - <<PY
import pathlib
b = pathlib.Path("$R19/pi_natives.android-arm64.node").read_bytes()
assert b.count(b"__piNativesV18_1_19") == 1
pathlib.Path("$R20/pi_natives.android-arm64.node").write_bytes(b.replace(b"__piNativesV18_1_19", b"__piNativesV18_1_20"))
PY
cp "$R/bin/omp-termux" "$RAW/bin/omp-termux"
printf '#!/bin/sh\ncase "$*" in *api.github.com*) echo "{\\"tag_name\\": \\"v18.1.20\\"}"; exit 0;; esac\nexec /usr/bin/curl "$@"\n' >"$FB/curl"
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
P="$T/.bun/install/cache/@oh-my-pi/pi-natives@18.1.19@@@1"; TOOL="$T/usr/bin/omp-termux"
chk "引导后插件就位" "$(ls "$P/native" | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
chk "引导后工具持久化" "$([ -f "$T/.local/opt/omp-termux/bin/omp-termux" ] && echo yes)" "yes"
chk "软链落在 \$PREFIX/bin" "$(readlink "$T/usr/bin/omp-termux")" "$T/.local/opt/omp-termux/bin/omp-termux"
chk "引导临时目录已清" "$(ls -A "$T/tmp" | wc -l)" "0"
chk "引导未动 omp" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"

dev() { HOME=$T TMPDIR=$T/tmp PREFIX=$T/usr XDG_CONFIG_HOME=$T/.config TERMUX_VERSION=0.118 PATH="$FB:$PATH" \
	OMP_TERMUX_RAW_BASE="file://$RAW" OMP_TERMUX_RELEASE_BASE="$1" "$TOOL" ${2:-install} "${3:-}"; }

: >"$LOG"; dev "file://$R19" install >/tmp/v2.log 2>&1; chk "install(无参) exit=0" "$?" "0"
chk "install(无参)未升级 omp" "$(grep -c 'install -g' "$LOG" 2>/dev/null || true)" "0"
: >"$LOG"; dev "file://$R20" install latest >/tmp/v3.log 2>&1; chk "install latest exit=0" "$?" "0"
chk "调用了 bun 升级" "$(grep -o 'install -g @oh-my-pi/pi-coding-agent@18.1.20' "$LOG" | head -1)" "install -g @oh-my-pi/pi-coding-agent@18.1.20"
chk "新版包内插件就位" "$(ls "$T/.bun/install/cache/@oh-my-pi/pi-natives@18.1.20@@@1/native" 2>/dev/null | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
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
chk "坏脚本时旧副本完好" "$(sha256sum "$T/.local/opt/omp-termux/bin/omp-termux" | cut -c1-12)" "$keep"
chk "无 .new 残留" "$(ls "$T/.local/opt/omp-termux/bin" | tr '\n' ' ')" "omp-termux "
chk "设备无计划外文件" "$(find "$T" -type f -not -path '*/.config/*' -not -path '*/.bun/*' -not -path '*/.local/*' 2>/dev/null | tr '\n' ' ')" ""

echo "== 工作站侧冒烟(假 ssh/scp 当设备)"
TW=/tmp/vws; FSW=/tmp/vwsbin
case "$TW$FSW" in /tmp/*) ;; *) echo "verify: refusing to touch $TW$FSW" >&2; exit 1 ;; esac
rm -rf "$TW" "$FSW"
mkdir -p "$TW/.bun/install/cache/@oh-my-pi/pi-natives@18.1.19@@@1/native" "$TW/.config" "$FSW"
echo '{"name":"@oh-my-pi/pi-natives","version":"18.1.19"}' >"$TW/.bun/install/cache/@oh-my-pi/pi-natives@18.1.19@@@1/package.json"
printf '#!/bin/sh\nfor a in "$@"; do cmd="$a"; done\nHOME="%s" PATH="%s:$PATH" sh -c "$cmd"\n' "$TW" "$FSW" >"$FSW/ssh"
printf '#!/bin/sh\nfor a in "$@"; do [ -f "$a" ] && { mkdir -p "%s/.cache/omp-termux"; cp -f "$a" "%s/.cache/omp-termux/"; }; done\nexit 0\n' "$TW" "$TW" >"$FSW/scp"
printf '#!/bin/sh\nexit 0\n' >"$FSW/bun"
chmod +x "$FSW"/*
ws() { HOME=$TW XDG_CONFIG_HOME=$TW/.config OMP_TERMUX_HOST=user@device PATH="$FSW:$PATH" bash "$R/bin/omp-termux" "$@" >/tmp/vws.log 2>&1; }
for v in help doctor status verify; do ws "$v" && ok "工作站 $v exit=0" || no "工作站 $v 失败"; done
ws install 18.1.19 && ok "工作站 install 18.1.19 exit=0" || { no "工作站 install 失败"; tail -3 /tmp/vws.log | sed 's|^|       |'; }
chk "工作站安装后设备侧插件就位" "$(ls "$TW/.bun/install/cache/@oh-my-pi/pi-natives@18.1.19@@@1/native" | tr '\n' ' ')" "desktop-adapter.js pi_natives.android-arm64.node "
ws install-self && ok "工作站 install-self exit=0" || no "install-self 失败"
chk "install-self 建链" "$(readlink "$TW/.local/bin/omp-termux" 2>/dev/null)" "$TW/.local/opt/omp-termux/bin/omp-termux"
ws uninstall-self && ok "工作站 uninstall-self exit=0" || no "uninstall-self 失败"
chk "uninstall-self 清干净" "$([ -e "$TW/.local/opt/omp-termux" ] && echo exists || echo gone)" "gone"
rm -rf "$T" "$FB" "$RAW" "$R19" "$R20" "$LOG" "$TW" "$FSW"
echo
echo "失败项: $fail"
exit $fail
