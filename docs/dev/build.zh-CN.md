# 构建插件

[English](build.md) | [中文](build.zh-CN.md)

`dev/omp-termux-dev` 在检出目录里交叉编译插件,并在设备可经 ssh 访问时把插件装上去、就地验证。
设备侧工具见[设备端工具](tool.zh-CN.md)。

## 环境要求

需要一台工作站(在 Linux x86_64 上验证过),装有 `rustup`、`bun` ≥ 1.3.14、`cmake`、`ninja`、`git`、`curl`、
`unzip`,以及用于产物检查的 `file` 与 `readelf`(`nm` 可选)。NDK 按以下顺序查找:

1. `OMP_TERMUX_NDK`、`ANDROID_NDK_ROOT`、`ANDROID_NDK_HOME`、`ANDROID_NDK_LATEST_HOME`;
2. `ANDROID_HOME`、`~/Android/Sdk`、`~/.local/share/Android/Sdk`、`/opt/android-sdk` 下最新的 `ndk/*`;
3. `/opt/android-ndk`、`~/.local/share/android-ndk`。

缺什么,`./dev/omp-termux-dev doctor` 会列出来。

## 构建

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

不带版本号时构建上游最新的 release。在设备本机上运行时,改为编译设备已装的 pi-natives 版本(耗时以小时计,
建议放进 `tmux`)。`OMP_TERMUX_MODE` 可覆盖这个判断;通过 ssh 驱动设备的动词在设备模式下会拒绝执行。

## 源码与补丁

`fetch_source` 把上游 tag `v<version>` 克隆到 `work/src`,这是可丢弃的克隆:会被清空或硬重置,绝不手工修改。
`apply_patch` 用 `git apply` 严格应用内置的 `patches/*.patch`(不允许模糊匹配,不允许 3-way),并检查补丁应改到的
标记;只有头部写明当前 PR 的补丁文件才可用。没有可用文件时,会下载 PR diff。

## napi CLI

`@napi-rs/cli` 按上游 `package.json` 声明的版本独立安装到 `work/napi-cli`:
在 `packages/natives` 里直接 `bun install` 会解析整个 monorepo(~400 个包,~1.5 GB),而 CLI 单独只占 ~56 MB。
设备构建从 `packages/natives/node_modules` 解析 CLI;工作站路径把该目录链接到独立副本,存在真实目录时则安装进去。

## Opus

`prepare_opus` 只在 `Cargo.lock` 仍含 `audiopus_sys` 时运行:这类版本通过它自带 opus 源码,
`cross_build` 随后用 `LIBOPUS_LIB_DIR` 链接 `$OPUS_PREFIX`。
更新的版本改用 `opusic-sys`,其默认 `bundled` feature 用自己的源码树和 cmake 构建 opus。
该步骤会先删掉这个 crate 的构建目录,因为它没有声明 `rerun-if-env-changed`,Cargo 会复用主机 ABI 运行留下的 rlib。

## 交叉编译

`cross_build` 用 napi CLI 加 `--target aarch64-linux-android --profile ci` 构建到 `out/.build`;
NDK 以三种方式命名(`ANDROID_NDK_LATEST_HOME`、`ANDROID_NDK_HOME`、`ANDROID_NDK_ROOT`),
`ANDROID_PLATFORM` 为 API 24,`BINDGEN_EXTRA_CLANG_ARGS_*` 指向 sysroot。
`RUSTC_BOOTSTRAP` 限定为 `xutf,pi_natives`,让 N-API crate 能在设备自带的 stable rustc 上构建。

## 产物身份

loader 把 `__piNativesBuildVersion()` 与包版本比较,而 release 源码会让那个 64 字节槽留空:上游在链接后写入。
工作站路径自己运行上游的 `scripts/stamp-native-version.ts`;没有该工具的 release 必须以别的方式报告版本。
`finalize_artifact` 找到生成的 `pi_natives*.node`,写入版本、验证,
然后才替换 `out/pi_natives.android-arm64.node`,所以失败的运行会保留上一个可用产物。

## 产物检查

`verify_artifact` 在以下情况失败:不是 `ARM aarch64`、缺少 `.note.android.ident`、需要 `GLIBC_*` 版本,
或 NEEDED 中出现 `libc.so.6`/`ld-linux`。它还会检查 N-API 入口,以及产物报告的是否为请求的 release。

## 设备

```sh
./dev/omp-termux-dev device user@host     # save the target ($XDG_CONFIG_HOME/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

目标来自 `OMP_TERMUX_HOST`/`OMP_TERMUX_PORT`,否则是保存的配置文件。端口回退到 `ssh -G` 报告的值;
22 是 ssh 的默认值、没有任何配置,不是 Termux 端口,这时改用 8022。
每条远程命令都通过 ssh 以 `sh -c` 运行,否则 sshd 会使用登录 shell(fish、zsh 等),而这些片段是 POSIX 的。

每次运行把 `bin/omp-termux` 上传一次到设备的 `~/.cache/omp-termux/build`;工作站环境里的 `OMP_TERMUX_CACHE_HOME`
会改掉这个目录,相对路径按设备的 `HOME` 解析。EXIT trap 会删除该目录以及已经变空的父目录。
`install` 先只暂存工具,读取它的 `status` 中 `omp` 那一行作为要构建的版本;设备上还没有 omp 时用上游最新
release。所以冷构建失败时,设备上什么都没变。随后构建或准备产物,上传到同一个目录,通过暂存的工具运行
`install "<file>"`,最后运行 `verify`。`status` 与 `verify` 是同样的往返,但不改任何东西;暂存的工具自己解析
设备上的 bun 与 omp。

## 发布

`.github/workflows/build.yml` 是唯一的 CI。它运行 `./dev/omp-termux-dev build "$VERSION"`,
并发布 `omp-<version>` release,内容为 `out/pi_natives.android-arm64.node`,每个 omp 版本一个。
没有校验用的 CI,本地门禁是 `sh tests/verify.sh`。
