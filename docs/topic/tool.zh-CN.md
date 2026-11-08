# 设备工具:设计说明

[English](tool.md) | [中文](tool.zh-CN.md)

本文记录 `bin/omp-termux` 实现的规则及其原因。用户执行的命令见 `README.md`,另一半见 `build.md`。

## 两个半体,一套命名

`bin/omp-termux` 是设备侧:`install`、`status`、`verify` 和 `doctor` 作用于运行它的机器上的 pi-natives,
`help`、`update-self` 和 `uninstall-self` 在任何地方都能用。`dev/omp-termux-dev` source 这个工具,
因此插件的文件名、仓库名和输出辅助函数只存在一处;文件被直接执行时,只有它自己的分发逻辑会运行动词。

## 工具自己占用的位置

- 自己的副本:`~/.local/opt/omp-termux`;在 Termux 上从 `$PREFIX/bin` 链接过去,
  否则是 `$XDG_BIN_HOME` 或 `~/.local/bin`。`uninstall-self` 会把两者都删掉。
- 临时目录:`$OMP_TERMUX_CACHE_HOME`,否则 `$XDG_CACHE_HOME/omp-termux`,否则 `~/.cache/omp-termux`。
  下载、探针和日志都放在这里,用完即删。这个目录只归工具使用,所以清理旧文件时逐个删除,绝不做递归删除。
- 自更新检查结果:`$PREFIX/cache/self-update`;放在 prefix 下,`uninstall-self` 会随其余内容一并删掉。

## 环境只解析一次

`resolve_env` 读取 `BUN_INSTALL`、`XDG_*`、`HOME` 和 `PATH`;其后的每个动词只读它设置的值。
改变环境的步骤(安装 bun 或 omp)会再次调用它,其他位置不再重新推导任何路径。

bun 的安装根遵循 bun 自己的规则:`BUN_INSTALL`,否则 `$XDG_CACHE_HOME/.bun`,否则 `~/.bun`。
所有存在的根按这个顺序访问,`$HOME/.cache/.bun` 放在最后:它是 bun 的 XDG 时代布局,
只有通过 `XDG_CACHE_HOME` 才能到达,所以排在 bun 规则命名的根之后。相对路径会被忽略
——在这种路径下 bun 的全局安装会以 `EACCES` 失败——解析为 `/` 或 `$HOME` 的临时路径同样被忽略。

正在使用的根是第一个带有 `@oh-my-pi/pi-coding-agent` 的根,否则是第一个存在的根,否则是 bun 的默认根。
shell 会被固定在那里(`BUN_INSTALL`、`PATH`),因为 bun 安装到 `BUN_INSTALL` 指向的位置,
而不是 `PATH` 指向的位置。

构建半在上传工具之前就要在设备上执行命令,因此同一规则还有一份 POSIX 片段(`REMOTE_ROOT_PROBE`),
由设备自己求值。`tests/verify.sh` 会比较两边的答案。

## 设备实际加载的是什么

`natives_dirs` 列出所有已安装的 `@oh-my-pi/pi-natives`:bun 根的 cache(两种布局)、bun 全局树和 npm 全局树,
并按真实路径去重:下面的 Termux 修复会让同一个包以多种拼写可达。

loader 解析的副本是 `<root>/install/global/node_modules` 里的那个;根里没有时,回退到它持有的最新包。
路径中没有 `node_modules` 段(workspace 加载)时,loader 跳过版本检查;否则把 `__piNativesBuildVersion()`
与包版本比较,因此插件只会放进版本匹配的包。

插件的版本可以从链接后写入的 64 字节槽读出(`PI_NATIVES_VERSION_STAMP:<version>`);
该槽出现之前的版本改为导出一个按版本命名的 napi 名(`__piNativesV18_3_2`)。两种都接受,
因为设备上仍可能留着旧格式的副本。

## Termux 上的 bun 布局

`bun install -g` 留下的 `<root>/bin/omp` 解析到 `<root>/install/cache/<pkg>@<version>@@@1`,那里没有
`node_modules`,于是惰性导入的包会失败(`omp stats` 找不到 `@oh-my-pi/pi-natives`),而 CLI 其余部分能启动。
`link_global_tree` 把每个全局包链接进 `<cache>/node_modules`;它只刷新符号链接,遇到真实目录则不动,
因为 `ln -sfn` 指向目录时会在目录内部建链接。

## install 动词

目标按以下顺序解析:

| 参数 | 目标 |
|---|---|
| 一个 `.node` 文件 | 该产物;它自己的 stamp 就是版本 |
| 一个版本 | 该版本;即使领先于已发布的版本,也由调用者决定 |
| `latest` | 这里最新的 release;查询失败时保留已安装版本并给出警告 |
| 无参数 | `$OMP_TERMUX_VERSION`,否则设备正在运行的版本;一个都没有时用这里最新的 release |

随后 `device_install` 依次:

1. 修复 Termux 布局并读取已安装内容;
2. 把这里最新的 release 记进自更新缓存,免得 `status` 一直显示旧值;
3. 目标已就位且能加载时,清掉过期的全局条目,报告并以 0 退出,不下载任何东西;
4. 对工具自己选定的目标,如果设备运行的 omp 比这里已发布的更新就拒绝——这一步在当前状态检查之后,
   所以什么都没变的运行不会在途中被拒绝;
5. 缺少 bun 时安装它,下载插件(其 stamp 必须与目标一致),清掉过期的全局条目,安装 CLI;
   树偏离目标时在安装行里点名插件的包,随后再把这个 pin 去掉,让 manifest 只保留 CLI、由它的精确 pin 决定树;
6. 把 bun 提升到已安装 omp 的 `engines.bun` 下限——需要更新 bun 的 omp 无法启动,所以这发生在插件落地之前;
7. 把插件装进每个版本匹配的包(先 `.part` 再改名),验证,从 bun 的 cache 里清理严格更旧的副本
   (绝不穿过符号链接),最后安装工具自己。

这个顺序是为了避免设备上 omp 无法启动:插件先于 omp 被替换而取到,而 bun 在碰插件之前先达到下限。
被拒绝或失败的运行不会改动 manifest 和树。

## status 与 verify

`run_verify` 用 bun 加载每个已安装包的 `native/index.js`,并检查导出集合(Android 裁掉的模块应当缺失),
但只有 loader 解析的那一份能让整次运行失败:另一个 release 的残留包不必带有适配本平台的插件。
之后运行 `omp --version`;`omp` 是用户安装的那份,永远不是工具自己的。

## 自更新与 release 查询

除 `help` 和 `update-self` 外,`check_self_update` 在每个动词之前运行,且只在已安装副本上运行。
它通过条件 GET(`ETag`)把 `main` 的 SHA-256 与自己的比较,把结果缓存到 `$PREFIX/cache/self-update`,
缓存时长为 `OMP_TERMUX_UPDATE_TTL` 秒;两者不同时向 stderr 打印一行。
缓存与抓取它的副本绑定:被其他方式替换过的工具会重新检查,而不是报告一个并不存在的差异。
同一个文件还保存这里最新的 release,`status` 会显示它;解析到 release 的 install 会把它写回。

两处 release 查询都读取 `https://github.com/<repo>/releases/latest` 的 `Location` 头(去掉标签后缀),
而不使用 GitHub API:每小时 60 次配额是按 IP 计的,运营商 NAT 后的手机要与陌生人共享这份配额。
