# 设备工具

[English](tool.md) | [中文](tool.zh-CN.md)

`bin/omp-termux` 把 Android 插件装进 `omp` 所用的 pi-natives 包,并让 omp 与插件保持同一版本。
本文记录它实现的规则;命令见 [README](../../README.md),构建与发布见 [build.md](build.md)。

## 工具维护的位置

- 自己的副本:`~/.local/opt/omp-termux`;在 Termux 上从 `$TERMUX_PREFIX/bin` 链接过去,
  否则是 `$XDG_BIN_HOME` 或 `~/.local/bin`。
  `uninstall-self` 会把两者都删掉。新副本先放在旧副本旁边,再改名覆盖。
- 临时目录:`OMP_TERMUX_CACHE_HOME`,否则 `$XDG_CACHE_HOME/omp-termux`,否则 `~/.cache/omp-termux`。
  只有 `install` 和 `verify` 会打开它;每次运行得到一个 `run.<pid>` 目录,由 EXIT trap 删除,变空的根目录一并删除。
  打开目录时会回收进程已不存在的目录,仍活着的则保留。插件下载写在其中,因此不会把半个文件当成完整文件。
- 自更新缓存:`~/.local/opt/omp-termux/cache/self-update`,`uninstall-self` 会随其余内容一并删掉。

## 环境

`resolve_env` 是 `HOME`、`XDG_*`、`BUN_INSTALL` 和 `PATH` 的唯一读取者,也是解析后变量的唯一写入者;
安装 bun 或 omp 的步骤会再次调用它。其余函数只通过参数或这些变量取输入。

bun 的根遵循 bun 自己的规则:`BUN_INSTALL`,否则 `$XDG_CACHE_HOME/.bun`,否则 `~/.bun`;
更旧的 `~/.cache/.bun` 根仍会被搜索,排在最后。
相对路径会被忽略——在这种路径下 bun 的全局安装会以 `EACCES` 失败——
解析为 `/` 或 `$HOME` 的临时路径同样被忽略。

正在使用的根是第一个带有 `@oh-my-pi/pi-coding-agent` 的根,否则是第一个存在的根,否则是 bun 的默认根。
shell 会被固定在那里(`BUN_INSTALL`、`PATH`),因为 bun 安装到 `BUN_INSTALL` 指向的位置,而不是 `PATH` 指向的位置。

## 设备实际加载的是什么

`natives_dirs` 列出每个 bun 根(`install/cache` 与 `install/global`)下所有已安装的 `@oh-my-pi/pi-natives`,
并按真实路径去重。loader 解析的是 `<root>/install/global/node_modules` 里的那一份;
根里没有时,回退到它持有的最新包。它会把插件的版本与包版本比较,因此插件只会放进版本匹配的包。

插件的版本来自链接后写入的 64 字节槽(`PI_NATIVES_VERSION_STAMP:<version>`);
更旧的构建改为导出一个按版本命名的 napi 名(`__piNativesV18_3_2`)。两种都接受。

`bun install -g` 留下的 `<root>/bin/omp` 解析到 `<root>/install/cache/<pkg>@<version>@@@1`,那里没有
`node_modules`,于是惰性导入的包会失败(`omp stats` 找不到插件),而 CLI 其余部分能启动。
`link_global_tree` 把每个全局包链接进 `<cache>/node_modules`;它只刷新符号链接,遇到真实目录则不动,
因为 `ln -sfn` 指向目录时会在目录内部建链接。

## install

目标按以下顺序解析:

| 参数 | 目标 |
|---|---|
| 一个 `.node` 文件 | 该产物;以其报告的版本为目标 |
| 一个版本 | 该版本,即使领先于已发布的版本 |
| `latest` | 这里最新的 release;查询失败时保留已安装版本并给出警告 |
| 无参数 | `$OMP_TERMUX_VERSION`,否则设备正在运行的版本;一个都没有时用这里最新的 release |

随后 `cmd_install` 依次:

1. 把 bun 的全局包链接进 cache 树(`link_global_tree`),并读取已安装内容;
2. 解析目标,并把这里最新的 release 记进自更新缓存,免得 `status` 一直显示旧值;
3. 目标已就位、插件能加载且 `omp` 能启动时,清掉过期的全局条目,报告 `nothing to do`,不下载任何东西;
4. 对工具自己选定的目标,如果设备运行的 omp 比这里已发布的更新就拒绝;
5. 在碰 omp 之前先拿到插件:release 下载到临时目录且必须报告目标版本,本地文件也必须报告可读的版本;
6. 缺少 bun 时安装它,按目标版本安装 CLI,并把 bun 提升到已安装 omp 的 `engines.bun` 下限;
7. 把插件装进每个版本匹配的包(先复制到目标旁边,再改名),静默校验 loader 解析的副本,
   从 bun 的 cache 里清理严格更旧的副本,最后安装工具自己;
8. 报告 `omp <version> ready (<n> addon copies)`,有残留时追加数量。

进度(`fetching pi-natives <ver> for android-arm64`、`installing omp <ver>`、`installing the addon`)写到 stderr;
结果行写到 stdout。先取得插件再替换 omp,bun 也在碰插件之前达到下限,所以下载失败不会动到现有安装。
被拒绝的目标或失败的下载不会改动任何东西。

## status 与 verify

`status` 只把行写到 stdout:

```
tool      omp-termux v0.6.0 (adf4d632b9e2)
omp       18.18.3
addon     18.18.3  105 MB loaded
          18.18.0  105 MB leftover
newest    omp-18.18.3
paths     bun   ~/.bun
          omp   ~/.bun/bin/omp
          tool  ~/.local/opt/omp-termux/omp-termux
```

`tool` 是工具标签,`omp` 是 CLI 版本(不存在时为 `none`)——构建脚本读取这一行。
`addon` 行列出每个已安装副本及其大小,`newest` 在 release 缓存有值时出现,
`paths` 会把 `$HOME` 折叠成 `~`,除非设置了 `OMP_TERMUX_VERBOSE=1`。

`verify` 为每个插件写一行,再为 CLI 写一行:

```
addon  18.18.3  android-arm64  154 exports  ok (loaded)
addon  18.18.0  ok (leftover)
omp    18.18.3  starts         ok
```

最后输出 `omp-termux: verify ok`。行输出写到 stdout;进度(`==> ...`)、警告和错误写到 stderr。
`check_addons` 用 bun 加载 loader 解析的那一份和每一个旧副本,并检查导出集合(Android 裁掉的模块应当缺失)。
输出上最多列两行旧副本,再附一行 `addon  +N more leftovers (OMP_TERMUX_VERBOSE=1 lists them)`;
加载失败的旧副本总是列出,`OMP_TERMUX_VERBOSE=1` 时每行都带导出数。
只有 loader 解析的那一份能让整次运行失败:另一个 release 的残留包不必带有适配本平台的插件。
之后 `run_verify` 运行用户已有的 `omp`(取自 `PATH`,否则 bun 的根),当它不是 `$BUN_HOME/bin/omp` 时告警,
启动失败则判为失败。加载失败的副本会连同所在目录一起报告;安装失败时会提示执行 `omp-termux verify`。

`doctor` 把 `termux`、`uname`、`tool`、`bun`、`omp`、`addon` 和 `free` 行写到 stdout,缺少 bun 时告警。

## 自更新与 release 查询

除 `help` 和 `update-self` 外,`check_self_update` 在每个动词之前运行,且只在已安装副本上运行。
它抓取 `main`,把正文的 SHA-256 与自己的比较,把结果缓存到自己的 `cache/self-update`,
缓存时长为 `OMP_TERMUX_UPDATE_TTL` 秒;两者不同时,每次运行都向 stderr 打印一行。
缓存记录写入它的副本的哈希,因此被其他方式替换过的工具会重新检查,而不是报告一个过期的差异。
同一个文件还保存这里最新的 release,`status` 会显示它;解析到 release 的 install 会把它写回。

`update-self` 抓取脚本,运行 `bash -n`,比较哈希,然后才把新副本改名覆盖旧的;正文相同则报告 `already up to date`。

所有请求都经过唯一的辅助函数 `http URL OUT MAX`:一次 `curl -fsSL` 调用,带 `--retry 3`、`--connect-timeout 15`
和 `--max-time MAX`,打印 `<status> <effective URL>`。调用方按状态分类 404/4xx/5xx;`000` 或空状态表示网络失败。
release 查询跟随 `https://github.com/<repo>/releases/latest` 的重定向,而不用 GitHub API:
后者的每小时 60 次配额按 IP 计,运营商 NAT 下多台设备共用。

## 环境变量

工具使用 `OMP_TERMUX_REPO`、`OMP_TERMUX_RELEASE_BASE`、`OMP_TERMUX_RAW_BASE`、`OMP_TERMUX_VERSION`、
`OMP_TERMUX_NO_UPDATE_CHECK`、`OMP_TERMUX_UPDATE_TTL` 和 `OMP_TERMUX_VERBOSE`;
`OMP_TERMUX_CACHE_HOME` 同时决定工具的临时根和构建脚本的上传目录;
构建脚本使用 `OMP_TERMUX_NDK`、`OMP_TERMUX_MODE`、`OMP_TERMUX_HOST` 和 `OMP_TERMUX_PORT`。
默认值足以覆盖全新设备,不需要任何 export。
