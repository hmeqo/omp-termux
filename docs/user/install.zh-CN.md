# 安装细节

[English](install.md) | [中文](install.zh-CN.md)

[README](../../README.zh-CN.md) 里的一键安装命令会运行 `install`。脚本会:

1. 在缺少 bun 时先装上 bun;
2. 把 omp 升级到本仓库构建的最新版本;
3. 把匹配的插件复制进 pi-natives 包的 `native/` 目录;
4. 把 `omp-termux` 链接进 `PATH`。

参数会原样传给 `install`:在安装命令末尾加上 `-s -- 18.3.4`,就会安装 18.3.4 版。

装完如果终端仍找不到 `omp` 或 `omp-termux`,脚本会问要不要把它们加入 shell 启动配置;同意后开一个新终端即可。

## 更新检查

`main` 上有更新的 `omp-termux` 时,每次运行 `omp-termux` 都会在 stderr 提示一行,直到你更新。
设 `OMP_TERMUX_NO_UPDATE_CHECK=1` 可跳过这项检查,`OMP_TERMUX_UPDATE_TTL`(单位秒,默认 86400)调整检查间隔。
检查只访问 GitHub 上的 `main`,不发送遥测,也不发送任何标识。
