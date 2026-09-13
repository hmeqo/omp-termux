# Nerd Font icons on Termux

[English](font.md) | [中文](font.zh-CN.md)

omp draws its status line with Unicode symbols by default, so no extra font is needed. For the Nerd Font icons,
install one in Termux and point omp at the `nerd` preset.

## Font

```sh
curl -fL -o "$TMPDIR/maple.zip" \
  https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-unhinted.zip
unzip -o "$TMPDIR/maple.zip" -d "$TMPDIR/maple"
cp "$TMPDIR/maple/MapleMono-NF-Regular.ttf" ~/.termux/font.ttf
```

Restart the Termux app afterwards. Any Nerd Font works the same way.

## Verify

```sh
printf '\uf015 \uf07b \ue0b0\n'
```

Three icons mean the font is active.

## Point omp at it

```sh
omp config set symbolPreset nerd
```
