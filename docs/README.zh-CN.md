# omp-termux

[English](../README.md) | [中文](README.zh-CN.md)

`omp` 需要原生插件 `@oh-my-pi/pi-natives`,而上游没有为 Android 构建它,因此在 Termux 上会报错退出:
`Unsupported platform: android-arm64`。本仓库负责安装这个插件,并提供一个 `omp-termux` 命令,让两者保持同步。

## 安装

### 在 Termux 上

一条命令:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

设备要求 Android 7+(API 24)、aarch64,并装有 `curl`。脚本会安装缺失的 `bun` 与 omp(取本仓库已发布的最新构建),
再把与你的 `@oh-my-pi/pi-natives` 匹配的插件放进 `omp` 所用包的 `native/` 目录,并把 `omp-termux` 留在 PATH 上。
启动 `omp`(已在运行则重启)能跑起来即表示插件已就位。
之后用 `omp-termux install latest` 让两者保持同步。

### 保持同步

```sh
omp-termux install latest   # omp + addon up to the newest build published here
omp-termux update-self      # replace omp-termux itself
```

`main` 上有更新的 `omp-termux` 时,它会在 stderr 打一行提示;`OMP_TERMUX_NO_UPDATE_CHECK=1` 可关闭该检查,
`OMP_TERMUX_UPDATE_TTL`(秒,默认 86400)可调整检查间隔。

## 命令

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 让本机用上该版本并安装插件(`latest` = 本仓库已发布的最新构建,缺省 = 当前运行的版本);已经装上就跳过下载,只在需要时编译,设备上没有 bun/omp 时也会自动装好 |
| `omp-termux status` / `verify` | 查看装了哪个版本 / 检查插件是否正常加载 |
| `omp-termux update-self` | 把已安装的 `omp-termux` 换成仓库里的最新版本 |
| `omp-termux uninstall-self` | 从本设备移除工具及其缓存(omp 保留) |
| `omp-termux doctor` | 检查本设备的运行环境 |

从源码编译插件是本仓库的另一半:[编译插件](build.zh-CN.md)(另有 [英文版](build.md))。

## 注意事项

* 自 omp 18.4.1 起,`omp` 即使空闲也大约每秒写一次终端,而 Termux 会在每次写入后把视图拉回底部:
  翻阅回滚请用 `tmux`(`Ctrl-b [`),或用 Termux 0.119 及更新版本的 `SCROLL`(`⇳`)extra key。
  软键盘改变尺寸时也会如此,用 `omp config set tui.resizeScrollback preserve` 可避免。
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
