# Termux 上的 Nerd Font 图标

[English](font.md) | [中文](font.zh-CN.md)

omp 默认用 Unicode 符号绘制状态行,不需要额外字体。想用 Nerd Font 图标时,在 Termux 里装一款 Nerd Font,
再把 omp 切到 `nerd` 预设。

## 字体

```sh
V=MapleMono-NF
curl -fL -o "$TMPDIR/maple.zip" \
  "https://github.com/subframe7536/maple-font/releases/latest/download/$V-unhinted.zip"
unzip -o "$TMPDIR/maple.zip" -d "$TMPDIR/maple"
cp "$TMPDIR/maple/$V-Regular.ttf" ~/.termux/font.ttf
```

中文请改用 `V=MapleMono-NF-CN`:该变体更大(152 MB),普通版不含中文字形,中文会回退到系统字体。
装完重启 Termux 应用。其他 Nerd Font 同理。

## 验证

```sh
printf '\uf015 \uf07b \ue0b0\n'
```

出现三个图标就说明字体已生效。

## 让 omp 用上它

```sh
omp config set symbolPreset nerd
```
