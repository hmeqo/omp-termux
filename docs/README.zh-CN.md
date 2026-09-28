# omp-termux

[English](../README.md) | [中文](README.zh-CN.md)

`omp` 需要原生插件 `@oh-my-pi/pi-natives`,而上游没有为 Android 构建它,因此在 Termux 上会报错退出:
`Unsupported platform: android-arm64`。本仓库用来安装这个插件,并在设备上留下一个 `omp-termux` 命令,
方便日后保持同步。

## 安装

### 在 Termux 上

一条命令:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

设备要求 Android 7+(API 24)、aarch64,并装有 `curl`。脚本会安装缺失的 `bun` 与 omp(取本仓库已发布的最新构建),
再把匹配的插件放进 `omp` 所用包的 `native/` 目录;启动 `omp` 能跑起来即表示插件已就位。
之后用 `omp-termux install latest` 让两者保持同步。

### 保持同步

```sh
omp-termux install latest   # omp + addon up to the newest build published here
omp-termux update-self      # replace omp-termux itself
```

### 自己编译

在本仓库的检出目录里,用 [开发依赖](#开发) 中列出的工具:

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

这是本仓库的维护者那半边:它产出插件,并在手机可 ssh 访问时把它装到设备上、就地校验。
同一个脚本在设备上也能原生编译(耗时以小时计,建议放进 `tmux`);不带版本号时两者都编译上游最新版本。

```sh
./dev/omp-termux-dev device user@host     # save the target (~/.config/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

## 开发

`bin/omp-termux` 是设备端工具;`dev/omp-termux-dev` 是编译那半,它 source 前者以复用两边共用的名字与函数。
从源码构建需要一台工作站(在 Linux x86_64 上验证),装有 `rustup`、`bun` ≥ 1.3.14、Android NDK
(依次取 `OMP_TERMUX_NDK`、`ANDROID_NDK_ROOT`、`ANDROID_NDK_HOME`,或用 SDK 里最新的 `ndk/*`)、`cmake`、
`ninja`、`git`、`curl`、`unzip`。缺哪个,`./dev/omp-termux-dev doctor` 会指出来。

## 命令

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 让本机用上该版本并安装插件(`latest` = 本仓库已发布的最新构建,缺省 = 当前运行的版本);已经装上就跳过下载,只在需要时编译,设备上没有 bun/omp 时也会自动装好 |
| `omp-termux status` / `verify` | 查看装了哪个版本 / 检查插件是否正常加载 |
| `omp-termux update-self` | 把已安装的 `omp-termux` 换成仓库里的最新版本 |
| `omp-termux uninstall-self` | 从本设备移除工具及其缓存 |
| `omp-termux doctor` | 检查本设备的运行环境 |

编译是另一半,有自己的清单:`./dev/omp-termux-dev help`(`build`、`doctor`)。

## 说明

* 插件必须与你安装的 `@oh-my-pi/pi-natives` 版本一致;`omp-termux install` 会自动对齐两者。
* `main` 上有更新的 `omp-termux` 时,它会在 stderr 打一行提示;
  `OMP_TERMUX_NO_UPDATE_CHECK=1` 可关闭该检查,`OMP_TERMUX_UPDATE_TTL`(秒,默认 86400)可调整检查间隔。
* 设备上会留下插件与 `omp-termux`:安装会把工具放进 PATH,`omp-termux uninstall-self` 只移除工具,不动 omp。
* 安装后请重启 `omp`:正在运行的进程仍会使用旧插件。
* Termux 上弹出软键盘会让画面从头滚到底,
  执行 `omp config set tui.resizeScrollback preserve` 可避免。
* omp 默认用 Unicode 符号绘制状态行;想换成 Nerd Font 图标,见 [Termux 上的 Nerd Font 图标](font.zh-CN.md)
  (另有 [英文版](font.md))。

## 限制

* Android 上没有桌面自动化和原生剪贴板;剪贴板回退到 `termux-clipboard-set`。
* Android 上没有音频、语音识别与语音合成支持。
* 只构建 arm64-v8a;armv7 与 x86 模拟器未测试。

## 致谢与许可

Android 支持来自上游 [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350),
作者 [@anatoli-tsinovoy](https://github.com/anatoli-tsinovoy)。
上游项目为 [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
两者均采用 MIT 许可,见 [LICENSE](../LICENSE)。
