# 构建半:设计说明

[English](build.md) | [中文](build.zh-CN.md)

本文记录 `dev/omp-termux-dev` 做什么以及为什么。维护者执行的命令见 `../build.md`;设备工具见 `tool.md`。

## 在哪里运行

同一个动词在工作站和设备上含义不同,所以构建半会先判断自己在哪里(Termux 检测,`OMP_TERMUX_MODE` 可覆盖)。
在设备上,`build` 是通过上游 `packages/natives/scripts/build-bindings.ts` 的原生构建;在工作站上是交叉编译。
通过 ssh 驱动目标设备的动词在设备模式下会拒绝执行。

## 源码、补丁与依赖

`fetch_source` 把上游 tag `v<version>` 克隆到 `work/src`,这是可丢弃的克隆:会被清空或硬重置,绝不手工修改。
`apply_patch` 用 `git apply` 严格应用内置补丁(不允许模糊匹配,不允许 3-way),并检查补丁必须改到的标记;
只有头部写明当前 PR 的补丁文件才可用,因此 PR 更新后旧文件不会被误用。没有内置文件时,会下载 PR diff。

`@napi-rs/cli` 按上游 `package.json` 声明的版本独立安装到 `work/napi-cli`:在 `packages/natives` 里直接
`bun install` 会解析整个 monorepo(~400 个包,~1.5 GB),而 CLI 单独只占 ~67 个包。
设备构建从源码树运行 `build-bindings.ts`,因此从 `packages/natives/node_modules` 解析 CLI;
工作站路径把该目录链接到独立副本,存在真实目录时则安装进去。

## opus 路径

omp 18.1.22 及更早版本中,`opus` crate 通过 `audiopus_sys` 内置源码。从 18.2.0 起改用 `opusic-sys`,
其默认 `bundled` feature 用自己的源码树和 cmake 构建 opus;这里构建的 libopus 无人使用,
而且干净机器上根本不会获取 `audiopus_sys` 的源码。因此 `prepare_opus` 只在 `Cargo.lock` 仍含
`audiopus_sys` 时运行,并且先删掉该 crate 的构建目录,因为它没有声明 `rerun-if-env-changed`,
Cargo 会复用主机 ABI 运行留下的 rlib。

## 交叉编译

`cross_build` 用 napi CLI 以 `--target aarch64-linux-android --profile ci` 输出到 `out/.build`;
NDK 以三种方式命名(`ANDROID_NDK_LATEST_HOME`、`ANDROID_NDK_HOME`、`ANDROID_NDK_ROOT`),
`ANDROID_PLATFORM` 为 API 24,`BINDGEN_EXTRA_CLANG_ARGS_*` 指向 sysroot。
`RUSTC_BOOTSTRAP` 限定为 `xutf,pi_natives`,让 N-API crate 能在设备自带的 stable rustc 上构建。

## 产物身份

loader 把 `__piNativesBuildVersion()` 与包版本比较,而 release 源码会让那个 64 字节槽留空:上游在链接后写入。
工作站路径自己运行上游的 `scripts/stamp-native-version.ts`;没有该工具的 release 属于旧格式,无需写入。
`finalize_artifact` 找到生成的 `pi_natives*.node`,写入版本、验证,然后才替换
`out/pi_natives.android-arm64.node`,所以失败的运行会保留上一个可用产物。

`verify_artifact` 在以下情况失败:不是 `ARM aarch64`、缺少 `.note.android.ident`、需要 `GLIBC_*` 版本、
或 NEEDED 中出现 `libc.so.6`/`ld-linux`。它还会检查 N-API 入口,以及产物报告的是否为请求的 release。

## 设备访问

目标来自 `OMP_TERMUX_HOST`/`OMP_TERMUX_PORT`,否则是保存的 `~/.config/omp-termux/config`。
端口回退到 `ssh -G` 报告的值;22 表示 ssh 的默认值、没有任何配置,不是 Termux 端口,这时改用 8022。

每条远程命令都通过 ssh 以 `sh -c` 运行,否则 sshd 会使用登录 shell(fish、zsh 等),而这些片段是 POSIX 的。
临时目录相对于设备的 `HOME`,除非给出绝对路径;它为本次运行创建,存放上传的插件和工具,运行结束后删除。

`install` 先构建或准备好产物,再碰设备,这样冷构建失败发生在上传之前,而不是传了一半才失败。
然后它把设备的 omp 带到该版本,上传产物和工具,让工具在远端完成安装:被验证的改动就是工具本身,
所以设备运行的是本检出的那份副本。`status` 与 `verify` 是同样的往返,但不改任何东西。
