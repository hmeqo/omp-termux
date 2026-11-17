# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` 依赖原生插件 `@oh-my-pi/pi-natives`,而上游没有为 Android 构建它,所以在 Termux 上 omp 会以
`Unsupported platform: android-arm64` 退出。本仓库为 Termux 构建这个插件,并提供一个 `omp-termux` 命令,
让 omp 与插件始终保持同一版本。

## 环境要求

- Android 7.0 或更新的版本(API 24),aarch64
- `bash` 与 `curl`

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

脚本会:

1. 在缺少 bun 时先装上 bun;
2. 把 omp 升级到本仓库构建的最新版本;
3. 把匹配的插件复制进 pi-natives 包的 `native/` 目录;
4. 把 `omp-termux` 链接进 `PATH`。

参数会原样传给 `install`,所以 `... | sh -s -- 18.3.4` 会安装 18.3.4 版。

装完如果终端仍找不到 `omp` 或 `omp-termux`,脚本会问要不要把它们加入 shell 启动配置;同意后开一个新终端即可。

装好后启动 `omp` 验证;如果它原本就在运行,请重启一次。

`main` 上有更新的 `omp-termux` 时,每次运行 `omp-termux` 都会在 stderr 提示一行,直到你更新。
设 `OMP_TERMUX_NO_UPDATE_CHECK=1` 可跳过这项检查,`OMP_TERMUX_UPDATE_TTL`(单位秒,默认 86400)调整检查间隔。
检查只访问 GitHub 上的 `main`,不发送遥测,也不发送任何标识。

## 命令

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 安装该版本及其插件(`latest` = 本仓库最新的构建,不填 = 已安装的版本);已是最新时不做任何改动 |
| `omp-termux status` | 显示工具、omp、各个插件副本,以及本仓库最新的构建 |
| `omp-termux verify` | 检查插件能否加载、omp 能否启动 |
| `omp-termux update-self` | 用本仓库最新的版本替换已安装的 `omp-termux` |
| `omp-termux uninstall-self` | 从本设备移除工具及其自更新缓存(omp 保留) |
| `omp-termux doctor` | 检查本设备的运行环境 |

## 注意事项

* 在 Termux 中打开软键盘时画面会从顶部滚动;执行 `omp config set tui.resizeScrollback preserve` 可避免。
* Nerd Font 图标见 [docs/user/font.zh-CN.md](docs/user/font.zh-CN.md)(另有[英文版](docs/user/font.md))。
* `omp` 每次向终端输出,Termux 都会把视图拉回底部;可以试试 `tmux`(`Ctrl-b [`),
  或用 Termux 0.119 及以后版本里的 `SCROLL`(`⇳`)。
  omp 18.4.1 到 18.5.0 空闲时也会每秒重绘,所以回滚后大约一秒又会被拉回底部。

## 限制

* Android 上不支持桌面自动化和原生剪贴板,剪贴板改用 `termux-clipboard-set`。
* Android 上不支持音频、语音识别与语音合成。
* 只支持 arm64-v8a,armv7 与 x86 没有构建。

## 致谢与许可

Android 支持来自上游 [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350)。
上游项目为 [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
该项目与本仓库均采用 MIT 许可,署名见 [LICENSE](LICENSE)。
