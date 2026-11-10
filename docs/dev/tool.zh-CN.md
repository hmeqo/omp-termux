# 设备工具:设计说明

[English](tool.md) | [中文](tool.zh-CN.md)

本文记录 `bin/omp-termux` 实现的规则及其原因。用户执行的命令见 [README](../../README.md);另一半见 [构建半](build.md)。

## 两个半体,一套命名

`bin/omp-termux` 是设备侧:`install`、`status`、`verify` 和 `doctor` 作用于运行它的机器上的 pi-natives,
`help`、`update-self` 和 `uninstall-self` 在任何地方都能用。
`dev/omp-termux-dev` source 这个工具,
因此插件的文件名、仓库名、版本辅助函数和输出辅助函数只存在一处;
文件被直接执行时,只有它自己的分发逻辑会运行动词。

## 工具自己占用的位置

- 自己的副本:`~/.local/opt/omp-termux`;在 Termux 上从 `$PREFIX/bin` 链接过去,
  否则是 `$XDG_BIN_HOME` 或 `~/.local/bin`。
  `uninstall-self` 会把两者都删掉。
  新副本先放在旧副本旁边,再改名覆盖。
- 临时目录:`$OMP_TERMUX_CACHE_HOME`,否则 `$XDG_CACHE_HOME/omp-termux`,否则 `~/.cache/omp-termux`。
  只有 `install` 和 `verify` 会打开它;每次运行都有自己的 `run.<pid>` 目录,退出时删除。
  这个目录只归工具使用:只有运行目录会被递归删除,根目录只在为空时 `rmdir`。
- 自更新缓存:`$PREFIX/cache/self-update`;放在 prefix 下,`uninstall-self` 会随其余内容一并删掉。

## 环境只解析一次

`resolve_env` 是 `BIN_HOME`、`CACHE_HOME`、`TMP_HOME`、`BUN_DEFAULT`、`BUN_ROOTS`、
`BUN_HOME`、`BUN_BIN` 和 `OMP_BIN` 的唯一写入者;其后的函数只通过参数或这些值取输入。
`scratch_open` 为需要它的两个动词设置 `SCRATCH`。
改变环境的步骤(安装 bun 或 omp)会再次调用 `resolve_env`,其他位置不再重新推导任何路径。

bun 的安装根遵循 bun 自己的规则:`BUN_INSTALL`,否则 `$XDG_CACHE_HOME/.bun`,否则 `~/.bun`。
所有存在的根按这个顺序访问,`$HOME/.cache/.bun` 放在最后:
它是 bun 的 XDG 时代布局,只有通过 `XDG_CACHE_HOME` 才能到达,所以排在 bun 规则命名的根之后。
相对路径会被忽略——在这种路径下 bun 的全局安装会以 `EACCES` 失败——
解析为 `/` 或 `$HOME` 的临时路径同样被忽略。

正在使用的根是第一个带有 `@oh-my-pi/pi-coding-agent` 的根,否则是第一个存在的根,否则是 bun 的默认根。
shell 会被固定在那里(`BUN_INSTALL`、`PATH`),
因为 bun 安装到 `BUN_INSTALL` 指向的位置,而不是 `PATH` 指向的位置。

构建半不再重复这条规则:它上传工具,并询问其 `status` 的 `omp` 行。

## 临时目录

`OMP_TERMUX_CACHE_HOME`,否则 `$XDG_CACHE_HOME/omp-termux`,否则 `~/.cache/omp-termux` 为每次安装保存一个目录,
名为 `run.<pid>`,只有 `install` 和 `verify` 会创建。
下一次运行打开自己的目录时,会回收已死的目录(进程已不存在);活着的目录则保留,所以两次运行可以重叠。
本次运行的文件——下载的插件、loader 探针、校验日志——不会活过这次运行:
EXIT trap 会删除该目录,以及已经变空的缓存根。
插件下载写入该目录,因此不可能把半个文件当成完整文件。

## 设备实际加载的是什么

`natives_dirs` 列出 bun 根 cache(两种布局)和全局树下所有已安装的 `@oh-my-pi/pi-natives`,
并按真实路径去重:下面的 Termux 修复会让同一个包以多种拼写可达。
bun 是安装契约;不会搜索 npm 的全局树。

loader 解析的副本是 `<root>/install/global/node_modules` 里的那个;根里没有时,回退到它持有的最新包。
路径中没有 `node_modules` 段(workspace 加载)时,loader 跳过版本检查;
否则把 `__piNativesBuildVersion()` 与包版本比较,因此插件只会放进版本匹配的包。

插件的版本可以从链接后写入的 64 字节槽读出(`PI_NATIVES_VERSION_STAMP:<version>`);
该槽出现之前的版本改为导出一个按版本命名的 napi 名(`__piNativesV18_3_2`)。
两种都接受,因为设备上仍可能留着旧格式的副本。

## Termux 上的 bun 布局

`bun install -g` 留下的 `<root>/bin/omp` 解析到 `<root>/install/cache/<pkg>@<version>@@@1`,
那里没有 `node_modules`,于是惰性导入的包会失败:
`omp stats` 找不到 `@oh-my-pi/pi-natives`,而 CLI 其余部分能启动。
`link_global_tree` 把每个全局包链接进 `<cache>/node_modules`;
它只刷新符号链接,遇到真实目录则不动,因为 `ln -sfn` 指向目录时会在目录内部建链接。

## install 动词

目标按以下顺序解析:

| 参数 | 目标 |
|---|---|
| 一个 `.node` 文件 | 该产物;它自己的 stamp 就是版本 |
| 一个版本 | 该版本;即使领先于已发布的版本,也由调用者决定 |
| `latest` | 这里最新的 release;查询失败时保留已安装版本并给出警告 |
| 无参数 | `$OMP_TERMUX_VERSION`,否则设备正在运行的版本;一个都没有时用这里最新的 release |

本地文件与版本走同样的流程:它不是跳过 omp 的捷径。随后 `cmd_install` 依次:

1. 修复 Termux 布局并读取已安装内容;
2. 把这里最新的 release 记进自更新缓存,免得 `status` 一直显示旧值;
3. 目标已就位且能加载时,清掉过期的全局条目,报告 `nothing to do` 并以 0 退出,不下载任何东西;
4. 对工具自己选定的目标,如果设备运行的 omp 比这里已发布的更新就拒绝——
   这一步在当前状态检查之后,所以什么都没变的运行不会在途中被拒绝;
5. 在碰 omp 之前先拿到插件:release 下载到本次运行的临时目录(其 stamp 必须与目标一致),本地文件则原样使用;
6. 缺少 bun 时安装它,按目标版本安装 CLI,并把 bun 提升到已安装 omp 的 `engines.bun` 下限——
   需要更新 bun 的 omp 无法启动,所以这发生在插件落地之前;
7. 把插件装进每个版本匹配的包(先复制到目标旁边,再改名),静默校验 loader 解析的副本,
   从 bun 的 cache 里清理严格更旧的副本(绝不穿过符号链接),最后安装工具自己;
8. 报告 `omp <version> ready (<n> addon copies)`,有残留时追加数量。

进度信息(`fetching pi-natives <ver> for android-arm64`、`installing omp <ver>`、`installing the addon`)写到 stderr;
唯一的结果行写到 stdout。

这个顺序是为了避免设备上 omp 无法启动:插件先于 omp 被替换而到手,bun 在碰插件之前先达到下限。
被拒绝或失败的运行不会改动 manifest 和树。
插件通过 `stage_into` 落地:复制到 `<dst>.part.<pid>`,再改名覆盖目标。工具自己的副本同样先暂存再改名,
`update-self` 也是如此。

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

`tool` 是工具标签,`omp` 是 CLI 版本(不存在时为 `none`)——构建半正是解析这一行,
`addon` 行列出每个已安装副本及其大小,`newest` 在 release 缓存有值时出现,
`paths` 会把 `$HOME` 折叠成 `~`,除非设置了 `OMP_TERMUX_VERBOSE=1`。

`verify` 为每个插件写一行,再为 CLI 写一行:

```
addon  18.18.3  android-arm64  154 exports  ok (loaded)
addon  18.18.0  ok (leftover)
omp    18.18.3  starts         ok
```

最后输出 `omp-termux: verify ok`。
行输出写到 stdout;进度(`==> ...`)、警告和错误写到 stderr。
`check_addons` 用 bun 加载 loader 解析的那一份和每一个旧副本,并检查导出集合;输出上最多列两行旧副本
(加载失败的总是列出,`OMP_TERMUX_VERBOSE=1` 时全部列出)(Android 裁掉的模块应当缺失),
但只有 loader 解析的那一份能让整次运行失败:另一个 release 的残留包不必带有适配本平台的插件。
之后 `run_verify` 运行 `omp --version`;`omp` 是用户安装的那份,永远不是工具自己的。
加载失败的副本会连同所在目录一起报告;安装路径里,提示会指向 `omp-termux verify`。

## 自更新与 release 查询

除 `help` 和 `update-self` 外,`check_self_update` 在每个动词之前运行,且只在已安装副本上运行。
它抓取 `main`,把正文的 SHA-256 与自己的比较,把结果缓存到 `$PREFIX/cache/self-update`,
缓存时长为 `OMP_TERMUX_UPDATE_TTL` 秒;两者不同时向 stderr 打印一行进度。
没有条件请求,也没有 `ETag`。
缓存与抓取它的副本绑定:被其他方式替换过的工具会重新检查,而不是报告一个并不存在的差异。
同一个文件还保存这里最新的 release,`status` 会显示它;解析到 release 的 install 会把它写回。

`update-self` 抓取脚本,运行 `bash -n`,比较哈希,然后才把新副本改名覆盖旧的;
正文相同则报告 `already up to date`。

所有请求都经过唯一的辅助函数 `http URL OUT MAX`:
一次 `curl -fsSL` 调用,带 `--retry 3`、`--connect-timeout 15` 和 `--max-time MAX`,
打印 `<status> <effective URL>`。
404/4xx/5xx 由调用方分类;`000` 或空状态表示网络失败。
release 查询读取 `https://github.com/<repo>/releases/latest` 的重定向,而不使用 GitHub API:
每小时 60 次配额是按 IP 计的,运营商 NAT 后的手机要与陌生人共享这份配额。

外联访问是完备的:`raw.githubusercontent.com/<repo>/main/...`(引导与自更新)、
`github.com/<repo>/releases/latest`(重定向查询)、`github.com/<upstream>/releases/latest`(构建半的目标)、
`github.com/<repo>/releases/download/omp-<ver>/...`(插件)、
`github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64-android.zip`(bun)、
构建半的 `github.com/<upstream>.git` 克隆(本地补丁不匹配时还会取
`patch-diff.githubusercontent.com/raw/<upstream>/pull/6350.diff`),
以及发往 `OMP_TERMUX_HOST` 的 ssh/scp。不发送任何标识符、统计分析或遥测。

## 环境变量

工具使用 `OMP_TERMUX_REPO`、`OMP_TERMUX_RELEASE_BASE`、`OMP_TERMUX_RAW_BASE`、`OMP_TERMUX_CACHE_HOME`、
`OMP_TERMUX_VERSION`、`OMP_TERMUX_NO_UPDATE_CHECK`、`OMP_TERMUX_UPDATE_TTL` 和 `OMP_TERMUX_VERBOSE`;
构建半使用 `OMP_TERMUX_NDK`、`OMP_TERMUX_MODE`、`OMP_TERMUX_HOST` 和 `OMP_TERMUX_PORT`。
默认值足以覆盖裸设备,不需要任何 export。
