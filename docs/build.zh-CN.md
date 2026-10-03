# 编译插件

[English](build.md) | [中文](build.zh-CN.md)

这是本仓库的维护者那半边:它产出插件,并在手机可 ssh 访问时把它装到设备上、就地校验。
`bin/omp-termux` 是设备端工具;`dev/omp-termux-dev` 是编译那半,它 source 前者以复用两边共用的名字与函数。

## 依赖

需要一台工作站(在 Linux x86_64 上验证),装有 `rustup`、`bun` ≥ 1.3.14、Android NDK
(依次取 `OMP_TERMUX_NDK`、`ANDROID_NDK_ROOT`、`ANDROID_NDK_HOME`,或用 SDK 里最新的 `ndk/*`)、`cmake`、
`ninja`、`git`、`curl`、`unzip`。缺哪个,`./dev/omp-termux-dev doctor` 会指出来。

## 编译

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

不带版本号时编译上游最新版本,可以在工作站上编译,也可以在设备上原生编译(耗时以小时计,建议放进 `tmux`)。

## 装到设备上

```sh
./dev/omp-termux-dev device user@host     # save the target (~/.config/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

`./dev/omp-termux-dev help` 会列出全部动词(`build`、`install`、`status`、`verify`、`device`、`doctor`)。
