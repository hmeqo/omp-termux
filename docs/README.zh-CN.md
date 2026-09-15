# omp-termux

[English](../README.md) | [中文](README.zh-CN.md)

`omp` 需要原生插件 `@oh-my-pi/pi-natives`,而上游没有为 Android 构建它,因此在 Termux 上会报错退出:
`Unsupported platform: android-arm64`。本仓库用来安装这个插件,并在设备上留下一个 `omp-termux` 命令,
方便日后保持同步。

## 安装

### 预编译

需要设备上有 `curl`:如果缺 `bun` 或 omp,脚本会先把它们装上。

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

脚本会安装 `omp-termux`,并把与你 omp 版本匹配的插件装进 `omp` 所用包的 `native/` 目录:

```sh
omp-termux install          # 你自己升级过 omp 之后:把匹配的插件补回来
omp-termux install latest   # 把 omp 升到最新 release,并装上匹配的插件
omp-termux update-self      # 更新 omp-termux 自身
```

完成后再启动 `omp`:能跑起来就说明插件已就位。如果你的版本还没有,稍后再试一次,或用下面的方式自行构建。

### 从源码构建

在工作站上,需要 [环境要求](#环境要求) 里列出的工具:

```sh
omp-termux install-self         # 一次性:装到 PATH(~/.local/bin)
omp-termux device user@phone    # 一次性:记住设备(sshd,端口 8022)
omp-termux install              # 一条命令:编译、传输、在设备上安装、验证
omp-termux install latest       # 以后:升级设备上的 omp,并安装匹配的插件
```

## 环境要求

工作站(在 Linux x86_64 上验证):`rustup`、`bun` ≥ 1.3.14、Android NDK(依次取 `OMP_TERMUX_NDK`、
`ANDROID_NDK_ROOT`、`ANDROID_NDK_HOME`,或用 SDK 里最新的 `ndk/*`)、`cmake`、`ninja`、`git`、`curl`、
`unzip`、`ssh`。缺哪个,`omp-termux doctor` 会指出来。

设备:Android 7+(API 24)、aarch64,并开启 `sshd`(`pkg install openssh`)。缺 `bun` 或 omp 时会自动安装。

## 命令

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 让设备用上该版本并安装插件(`latest` = 最新上游 release,缺省 = 设备当前版本);只在需要时编译,设备上没有 bun/omp 时也会自动装好;在设备上,则对设备自身执行同样的操作 |
| `omp-termux status` / `verify` | 查看设备上装了哪个版本 / 检查插件是否正常加载 |
| `omp-termux build [version]` | 只编译产物,不碰设备 |
| `omp-termux device [user@host]` | 查看或设置设备地址 |
| `omp-termux update-self` | 把已安装的 `omp-termux` 换成仓库里的最新版本 |
| `omp-termux install-self` / `uninstall-self` | 可选:把本工具装到 PATH(`~/.local/opt/omp-termux`、`~/.local/bin/omp-termux`),或卸载 |
| `omp-termux doctor` | 检查交叉工具链 |

## 说明

* 插件必须与你安装的 `@oh-my-pi/pi-natives` 版本一致;`omp-termux install` 会自动对齐两者。
* 设备上会留下插件与 `omp-termux`;`omp-termux uninstall-self` 只移除工具,不动 omp。
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
