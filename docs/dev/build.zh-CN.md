# 编译插件

[English](build.md) | [中文](build.zh-CN.md)

`dev/omp-termux-dev` 在检出目录里交叉编译插件,设备可通过 ssh 访问时,再把插件装上去并就地校验。
它是构建半;设备工具见 [设备工具](tool.md)。

## 依赖

需要一台工作站(在 Linux x86_64 上验证),装有 `rustup`、`bun` ≥ 1.3.14、Android NDK
(依次取 `OMP_TERMUX_NDK`、`ANDROID_NDK_ROOT`、`ANDROID_NDK_HOME`,或用 SDK 里最新的 `ndk/*`)、`cmake`、
`ninja`、`git`、`curl`、`unzip`,以及用于产物校验的 `file` 和 `readelf`(`nm` 存在时会额外检查)。
NDK 是系统的事:SDK、包管理器或环境已经提供的那个就用,这里不附带私有副本。
缺哪个,`./dev/omp-termux-dev doctor` 会指出来。

## 编译

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

不带版本号时,工作站上编译上游最新版本;在设备上原生编译的是设备当前运行的版本(耗时以小时计,建议放进 `tmux`)。
同一个动词在两种模式下含义不同:`OMP_TERMUX_MODE` 可覆盖检测结果,
通过 ssh 驱动目标设备的动词在设备模式下会拒绝执行。

## 源码、补丁与依赖

`fetch_source` 把上游 tag `v<version>` 克隆到 `work/src`,这是可丢弃的克隆:会被清空或硬重置,绝不手工修改。
`apply_patch` 用 `git apply` 严格应用内置的 `patches/*.patch`(不允许模糊匹配,不允许 3-way),并检查补丁必须改到的标记;
只有头部写明当前 PR 的补丁文件才可用,因此 PR 更新后旧文件不会被误用。
没有可用文件时,会下载 PR diff。

`@napi-rs/cli` 按上游 `package.json` 声明的版本独立安装到 `work/napi-cli`:
在 `packages/natives` 里直接 `bun install` 会解析整个 monorepo(~400 个包,~1.5 GB),而 CLI 单独只占 ~56 MB。
设备构建从 `packages/natives/node_modules` 解析 CLI;工作站路径把该目录链接到独立副本,存在真实目录时则安装进去。

## opus 路径

omp 18.1.22 及更早版本中,`opus` crate 通过 `audiopus_sys` 内置源码。
从 18.2.0 起改用 `opusic-sys`,其默认 `bundled` feature 用自己的源码树和 cmake 构建 opus;
这里构建的 libopus 无人使用,而且干净机器上根本不会获取 `audiopus_sys` 的源码。
因此 `prepare_opus` 只在 `Cargo.lock` 仍含 `audiopus_sys` 时运行,
并且先删掉该 crate 的构建目录,因为它没有声明 `rerun-if-env-changed`,Cargo 会复用主机 ABI 运行留下的 rlib。

## 交叉编译

`cross_build` 用 napi CLI 以 `--target aarch64-linux-android --profile ci` 输出到 `out/.build`;
NDK 以三种方式命名(`ANDROID_NDK_LATEST_HOME`、`ANDROID_NDK_HOME`、`ANDROID_NDK_ROOT`),
`ANDROID_PLATFORM` 为 API 24,`BINDGEN_EXTRA_CLANG_ARGS_*` 指向 sysroot。
`RUSTC_BOOTSTRAP` 限定为 `xutf,pi_natives`,让 N-API crate 能在设备自带的 stable rustc 上构建。

## 产物身份

loader 把 `__piNativesBuildVersion()` 与包版本比较,而 release 源码会让那个 64 字节槽留空:上游在链接后写入。
工作站路径自己运行上游的 `scripts/stamp-native-version.ts`;没有该工具的 release 属于旧格式,无需写入。
`finalize_artifact` 找到生成的 `pi_natives*.node`,写入版本、验证,
然后才替换 `out/pi_natives.android-arm64.node`,所以失败的运行会保留上一个可用产物。

`verify_artifact` 在以下情况失败:不是 `ARM aarch64`、缺少 `.note.android.ident`、需要 `GLIBC_*` 版本、
或 NEEDED 中出现 `libc.so.6`/`ld-linux`。它还会检查 N-API 入口,以及产物报告的是否为请求的 release。

## 装到设备上

```sh
./dev/omp-termux-dev device user@host     # save the target (~/.config/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

目标来自 `OMP_TERMUX_HOST`/`OMP_TERMUX_PORT`,否则是保存的 `~/.config/omp-termux/config`。
端口回退到 `ssh -G` 报告的值;22 表示 ssh 的默认值、没有任何配置,不是 Termux 端口,这时改用 8022。

每条远程命令都通过 ssh 以 `sh -c` 运行,否则 sshd 会使用登录 shell(fish、zsh 等),而这些片段是 POSIX 的。

`install`(以及 `status`/`verify`)每次运行把 `bin/omp-termux` 上传一次到设备的 `~/.cache/omp-termux/build`,
设置了 `OMP_TERMUX_CACHE_HOME` 时放在其下,值不是绝对路径时相对于设备的 `HOME`。
EXIT trap 会删除该目录以及已经变空的父目录。
不带参数时,`install` 询问已暂存的工具的 `status`,读取 `omp` 行作为要构建的版本;
设备上还没有 omp 时用上游最新 release。
这里没有 bun 或 omp 逻辑:暂存的工具自己解析根并配好设备。

`install` 先只暂存工具并读取设备状态,然后再构建或准备产物:冷构建失败发生在设备上任何改动之前。
它把产物上传到同一个临时目录,通过暂存的工具运行 `install "<file>"`,再运行 `verify`;
`status` 与 `verify` 是同样的往返,但不改任何东西。

## 发布

`.github/workflows/build.yml` 是唯一的 CI。它运行 `./dev/omp-termux-dev build "$VERSION"`,
并发布 `omp-<version>` release,内容为 `out/pi_natives.android-arm64.node`;
每个 omp 版本一个 release,因为插件只会装进版本匹配的包。
没有校验用的 CI,本地门禁是 `sh tests/verify.sh`。
