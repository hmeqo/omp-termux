# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` 需要原生插件 `@oh-my-pi/pi-natives`,上游没有为 Android 构建它,因此在 Termux 上会报错退出:
`Unsupported platform: android-arm64`。本仓库负责安装这个插件,并提供一个 `omp-termux` 命令,让两者保持同步。

## 安装

在 Termux 上一条命令:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

设备要求 Android 7+(API 24)、aarch64,并装有 `curl`。
脚本会安装缺失的 `bun` 与 omp(取本仓库已发布的最新构建),
再把与你的 `@oh-my-pi/pi-natives` 匹配的插件放进 `omp` 所用包的 `native/` 目录,
并把 `omp-termux` 留在 `PATH` 上。
引导脚本会把参数转交给 `install`,所以 `... | sh -s -- 18.3.4` 会安装该版本。
启动 `omp`(已在运行则重启)能跑起来即表示插件已就位。
之后用 `omp-termux install latest` 让两者保持同步。

`main` 上有更新的 `omp-termux` 时,它会在 stderr 打一行提示;
`OMP_TERMUX_NO_UPDATE_CHECK=1` 可关闭该检查,`OMP_TERMUX_UPDATE_TTL`(秒,默认 86400)可调整检查间隔。

## 命令

设备工具:

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 让本机用上该版本并安装插件(`latest` = 本仓库已发布的最新构建,缺省 = 当前运行的版本);已经装上就跳过下载,设备上没有 bun/omp 时也会自动装好 |
| `omp-termux status` | 显示工具、omp、各个插件副本以及本仓库最新的构建 |
| `omp-termux verify` | 检查插件能否加载、omp 能否启动 |
| `omp-termux update-self` | 把已安装的 `omp-termux` 换成仓库里的最新版本 |
| `omp-termux uninstall-self` | 从本设备移除工具及其自更新缓存(omp 保留) |
| `omp-termux doctor` | 检查本设备的运行环境 |

构建半(在检出目录里运行):

| 命令 | 说明 |
|---|---|
| `./dev/omp-termux-dev build [version]` | 为 android-arm64 交叉编译插件 |
| `./dev/omp-termux-dev install [version\|file]` | 需要时编译,上传到目标设备并安装、校验 |
| `./dev/omp-termux-dev status` / `verify` | 询问目标设备当前运行的版本 / 插件能否加载 |
| `./dev/omp-termux-dev device [user@host]` | 显示或保存目标设备 |
| `./dev/omp-termux-dev doctor` | 检查构建在本机需要什么 |

编译插件:[编译插件](docs/dev/build.zh-CN.md)(另有 [英文版](docs/dev/build.md))。
设备工具的设计:[设备工具](docs/dev/tool.zh-CN.md)(另有 [英文版](docs/dev/tool.md))。

## 注意事项

* Termux 上弹出软键盘会让画面从头滚到底,执行 `omp config set tui.resizeScrollback preserve` 可避免。
* omp 默认用 Unicode 符号绘制状态行;想换成 Nerd Font 图标,见 [Termux 上的 Nerd Font 图标](docs/user/font.zh-CN.md)
  (另有 [英文版](docs/user/font.md))。
* Termux 会在 `omp` 每次写终端后把视图拉回底部;
  遇到时,可以试试 `tmux`(`Ctrl-b [`),或用 Termux 0.119 及更新版本中的 `SCROLL`(`⇳`)extra key 冻结视图。
* omp 18.4.1 到 18.5.0 空闲时也会每秒写一次终端,回滚后大约一秒就又被拉回底部。

## 限制

* Android 上没有桌面自动化和原生剪贴板;剪贴板回退到 `termux-clipboard-set`。
* Android 上没有音频、语音识别与语音合成支持。
* 只构建 arm64-v8a;armv7 与 x86 模拟器未测试。

## 隐私

没有遥测、没有标识符,也没有统计分析。
所有网络请求都发往下列端点之一,除请求本身外不携带任何内容:

* `raw.githubusercontent.com/<repo>/main/...`,用于引导安装与自更新检查;
* `github.com/<repo>/releases/latest`,用于重定向查询本仓库最新的构建;
* `github.com/<upstream>/releases/latest`,用于取构建半要针对的上游最新版本;
* `github.com/<repo>/releases/download/omp-<ver>/...`,用于下载插件;
* `github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64-android.zip`,仅在缺少 bun 时;
* `github.com/<upstream>.git`,构建半克隆上游时;没有匹配的本地补丁时还会取
  `patch-diff.githubusercontent.com/raw/<upstream>/pull/6350.diff`;
* ssh/scp 到 `OMP_TERMUX_HOST`,构建半驱动设备时。

`OMP_TERMUX_NO_UPDATE_CHECK=1` 可关闭自更新检查;`OMP_TERMUX_UPDATE_TTL` 控制检查频率。

## 致谢与许可

Android 支持来自上游 [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350)。
上游项目为 [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
两者均采用 MIT 许可,署名见 [LICENSE](LICENSE)。
